import { createServer } from "http";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { readFile, writeFile, mkdir } from "fs/promises";
import { existsSync } from "fs";
import { randomUUID } from "crypto";

const __dirname = dirname(fileURLToPath(import.meta.url));
const DATA_DIR = join(__dirname, "../data");
const STORE_FILE = join(DATA_DIR, "bills.json");

function startOfMonthKey(d = new Date()) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

async function ensureStoreFile() {
  if (!existsSync(DATA_DIR)) {
    await mkdir(DATA_DIR, { recursive: true });
  }

  try {
    const raw = await readFile(STORE_FILE, "utf8");
    return JSON.parse(raw);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
    const seed = {
      bills: [],
      payments: {},
      pushTokens: [],
    };
    await writeFile(STORE_FILE, JSON.stringify(seed, null, 2));
    return seed;
  }
}

let store = await ensureStoreFile();

async function persist() {
  await writeFile(STORE_FILE, JSON.stringify(store, null, 2));
}

function withPaymentStatus(month) {
  const paid = store.payments?.[month] || {};
  return store.bills.map((bill) => ({
    ...bill,
    isPaid: Boolean(paid[bill.id]),
  }));
}

function totalsForMonth(month) {
  const bills = withPaymentStatus(month);
  const total = bills.reduce((sum, bill) => sum + Number(bill.amount || 0), 0);
  const paid = bills.reduce(
    (sum, bill) => sum + (bill.isPaid ? Number(bill.amount || 0) : 0),
    0,
  );
  return {
    total,
    paid,
    remaining: total - paid,
  };
}

function applyCors(res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader(
    "Access-Control-Allow-Methods",
    "GET,POST,PUT,DELETE,OPTIONS",
  );
  res.setHeader(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization, Accept",
  );
}

function sendJson(res, statusCode, payload) {
  applyCors(res);
  res.writeHead(statusCode, { "Content-Type": "application/json" });
  res.end(JSON.stringify(payload));
}

function isValidExpoToken(token = "") {
  return typeof token === "string" && token.startsWith("ExponentPushToken[");
}

async function parseJsonBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 1_000_000) {
        reject(new Error("Payload too large"));
        req.destroy();
      }
    });
    req.on("end", () => {
      if (!body) return resolve({});
      try {
        resolve(JSON.parse(body));
      } catch (error) {
        reject(new Error("Invalid JSON"));
      }
    });
    req.on("error", reject);
  });
}

async function sendExpoPushNotifications(messages) {
  if (!messages.length) return [];

  const response = await fetch("https://exp.host/--/api/v2/push/send", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify(messages),
  });

  let data = null;
  try {
    data = await response.json();
  } catch (error) {
    // Expo sometimes responds with empty body on failure – surface status text
  }

  if (!response.ok) {
    const message =
      data?.errors?.map((err) => err.message).join(", ") ||
      response.statusText ||
      "Expo push request failed";
    throw new Error(message);
  }

  return Array.isArray(data?.data) ? data.data : data;
}

async function createChatCompletion({
  message,
  monthKey,
  bills,
  totals,
}) {
  if (!process.env.OPENAI_API_KEY) {
    return {
      status: 503,
      body: {
        error: "OpenAI API key not configured",
        reply:
          "The assistant service is unavailable because the OpenAI API key is not configured on the server.",
      },
    };
  }

  const systemPrompt = `You are BillsGPT, a helpful assistant that answers questions about a user's recurring bills. Today's month key is ${monthKey}. Be concise but helpful. If the user asks about totals, compute them from the provided data. If something is unknown, say so.`;

  const billContext = bills
    .map(
      (bill) =>
        `${bill.name} (id: ${bill.id}) — due on day ${bill.dueDay}, amount ${Number(bill.amount).toFixed(2)}. Notes: ${bill.notes || "none"}. Paid: ${bill.isPaid ? "yes" : "no"}.`,
    )
    .join("\n");

  const requestPayload = {
    model: process.env.OPENAI_MODEL || "gpt-4o-mini",
    temperature: 0.2,
    messages: [
      { role: "system", content: systemPrompt },
      {
        role: "user",
        content: `Here is the list of bills for ${monthKey} with payment status and notes:\n${billContext || "No bills on file."}\n\nTotals: total due ${totals.total.toFixed(2)}, paid ${totals.paid.toFixed(2)}, remaining ${totals.remaining.toFixed(2)}.\n\nUser question: ${message}`,
      },
    ],
  };

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
    },
    body: JSON.stringify(requestPayload),
  });

  const data = await response.json();
  if (!response.ok) {
    const errorMessage =
      data?.error?.message || `OpenAI request failed with status ${response.status}`;
    return {
      status: response.status,
      body: { error: errorMessage },
    };
  }

  const reply = data?.choices?.[0]?.message?.content?.trim();
  return {
    status: 200,
    body: { reply: reply || "I couldn't generate a response just now." },
  };
}

const server = createServer(async (req, res) => {
  applyCors(res);

  if (req.method === "OPTIONS") {
    res.writeHead(204);
    return res.end();
  }

  const url = new URL(req.url ?? "/", `http://${req.headers.host}`);
  const pathname = url.pathname;

  try {
    if (req.method === "GET" && pathname === "/") {
      return sendJson(res, 200, {
        status: "ok",
        docs: "See README.md for API usage.",
      });
    }

    if (req.method === "GET" && pathname === "/api/bills") {
      const monthKey = url.searchParams.get("month") || startOfMonthKey();
      return sendJson(res, 200, withPaymentStatus(monthKey));
    }

    if (req.method === "POST" && pathname === "/api/bills") {
      let body;
      try {
        body = await parseJsonBody(req);
      } catch (error) {
        return sendJson(res, 400, { error: error.message });
      }

      const { id, name, dueDay, amount, notes } = body || {};
      if (!name) {
        return sendJson(res, 400, { error: "name is required" });
      }
      if (dueDay === undefined || Number.isNaN(Number(dueDay))) {
        return sendJson(res, 400, { error: "dueDay must be a number" });
      }

      const billId = (id || "").trim() || randomUUID();
      if (store.bills.some((bill) => bill.id === billId)) {
        return sendJson(res, 409, {
          error: `Bill with id "${billId}" already exists`,
        });
      }

      const newBill = {
        id: billId,
        name: String(name),
        dueDay: Number(dueDay),
        amount: Number(amount || 0),
        notes: notes ? String(notes) : "",
      };

      store.bills.push(newBill);
      await persist();
      return sendJson(res, 201, newBill);
    }

    const billIdMatch = pathname.match(/^\/api\/bills\/([^/]+)$/);
    if (billIdMatch && req.method === "PUT") {
      let body;
      try {
        body = await parseJsonBody(req);
      } catch (error) {
        return sendJson(res, 400, { error: error.message });
      }

      const billId = decodeURIComponent(billIdMatch[1]);
      const bill = store.bills.find((item) => item.id === billId);
      if (!bill) {
        return sendJson(res, 404, { error: "Bill not found" });
      }

      const { name, dueDay, amount, notes } = body || {};
      if (name !== undefined) bill.name = String(name);
      if (dueDay !== undefined) bill.dueDay = Number(dueDay);
      if (amount !== undefined) bill.amount = Number(amount);
      if (notes !== undefined) bill.notes = notes ? String(notes) : "";

      await persist();
      return sendJson(res, 200, bill);
    }

    if (billIdMatch && req.method === "DELETE") {
      const billId = decodeURIComponent(billIdMatch[1]);
      const index = store.bills.findIndex((item) => item.id === billId);
      if (index === -1) {
        return sendJson(res, 404, { error: "Bill not found" });
      }
      store.bills.splice(index, 1);
      for (const month of Object.keys(store.payments || {})) {
        delete store.payments[month][billId];
      }
      await persist();
      res.writeHead(204);
      return res.end();
    }

    const paidMatch = pathname.match(/^\/api\/bills\/([^/]+)\/paid$/);
    if (paidMatch && req.method === "POST") {
      let body;
      try {
        body = await parseJsonBody(req);
      } catch (error) {
        return sendJson(res, 400, { error: error.message });
      }

      const billId = decodeURIComponent(paidMatch[1]);
      if (!store.bills.some((bill) => bill.id === billId)) {
        return sendJson(res, 404, { error: "Bill not found" });
      }
      const monthKey = body?.month || startOfMonthKey();
      if (!store.payments[monthKey]) {
        store.payments[monthKey] = {};
      }
      if (body?.isPaid) {
        store.payments[monthKey][billId] = true;
      } else {
        delete store.payments[monthKey][billId];
      }
      await persist();
      return sendJson(res, 200, {
        id: billId,
        month: monthKey,
        isPaid: Boolean(store.payments[monthKey][billId]),
      });
    }

    if (req.method === "POST" && pathname === "/api/push/register") {
      let body;
      try {
        body = await parseJsonBody(req);
      } catch (error) {
        return sendJson(res, 400, { error: error.message });
      }

      const token = body?.token;
      if (!token) {
        return sendJson(res, 400, { error: "token is required" });
      }

      const exists = store.pushTokens.find((entry) => entry.token === token);
      if (!exists) {
        store.pushTokens.push({
          token,
          platform: body?.platform || "unknown",
        });
        await persist();
      }

      return sendJson(res, 200, { ok: true, token });
    }

    if (req.method === "POST" && pathname === "/api/push/unregister") {
      let body;
      try {
        body = await parseJsonBody(req);
      } catch (error) {
        return sendJson(res, 400, { error: error.message });
      }

      const token = body?.token;
      if (!token) {
        return sendJson(res, 400, { error: "token is required" });
      }

      store.pushTokens = store.pushTokens.filter((entry) => entry.token !== token);
      await persist();
      return sendJson(res, 200, { ok: true });
    }

    if (req.method === "POST" && pathname === "/api/push/send-upcoming") {
      let body;
      try {
        body = await parseJsonBody(req);
      } catch (error) {
        return sendJson(res, 400, { error: error.message });
      }

      const monthKey = body?.month || startOfMonthKey();
      const bills = withPaymentStatus(monthKey);
      const now = new Date();
      const upcoming = bills.filter((bill) => {
        const due = new Date(now.getFullYear(), now.getMonth(), bill.dueDay);
        const diffDays = (due - now) / (1000 * 60 * 60 * 24);
        return diffDays >= 0 && diffDays <= 7 && !bill.isPaid;
      });

      if (!upcoming.length) {
        return sendJson(res, 200, { sent: 0, reason: "no-upcoming" });
      }

      const tokens = store.pushTokens.filter((entry) => isValidExpoToken(entry.token));
      if (!tokens.length) {
        return sendJson(res, 200, { sent: 0, reason: "no-tokens" });
      }

      const messageBody = upcoming
        .map(
          (bill) =>
            `${bill.name} is due on day ${bill.dueDay} (${Number(bill.amount).toFixed(2)})`,
        )
        .join("\n");

      const notifications = tokens.map((entry) => ({
        to: entry.token,
        sound: "default",
        title: "Bills due soon",
        body: messageBody,
        data: {
          month: monthKey,
          bills: upcoming.map((bill) => bill.id),
        },
      }));

      try {
        const tickets = await sendExpoPushNotifications(notifications);
        return sendJson(res, 200, { sent: notifications.length, tickets });
      } catch (error) {
        return sendJson(res, 502, {
          error: "Failed to send push notifications",
          details: error.message,
        });
      }
    }

    if (req.method === "POST" && pathname === "/api/chat") {
      let body;
      try {
        body = await parseJsonBody(req);
      } catch (error) {
        return sendJson(res, 400, { error: error.message });
      }

      const message = body?.message;
      if (!message) {
        return sendJson(res, 400, { error: "message is required" });
      }

      const monthKey = body?.month || startOfMonthKey();
      const bills = withPaymentStatus(monthKey);
      const totals = totalsForMonth(monthKey);

      try {
        const result = await createChatCompletion({
          message,
          monthKey,
          bills,
          totals,
        });
        return sendJson(res, result.status, result.body);
      } catch (error) {
        return sendJson(res, 500, {
          error: "Failed to contact OpenAI",
          details: error.message,
        });
      }
    }

    sendJson(res, 404, { error: "Not found" });
  } catch (error) {
    console.error("Unhandled server error", error);
    sendJson(res, 500, { error: "Internal server error" });
  }
});

const PORT = Number(process.env.PORT || 4000);
server.listen(PORT, () => {
  console.log(`Bills API listening on http://localhost:${PORT}`);
});
