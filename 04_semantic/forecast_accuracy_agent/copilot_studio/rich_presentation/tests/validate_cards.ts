import { readdir, readFile } from "node:fs/promises";
import { AdaptiveCard } from "adaptivecards";

const root = new URL("../cards/ac15/", import.meta.url);
const names = (await readdir(root)).filter((name) => name.endsWith(".json")).sort();
const failures: string[] = [];

for (const name of names) {
  const path = new URL(name, root);
  const cardJson = JSON.parse(await readFile(path, "utf8")) as { version?: string };
  if (cardJson.version !== "1.5") {
    failures.push(`${name}: expected Adaptive Cards 1.5`);
    continue;
  }

  const card = new AdaptiveCard();
  try {
    card.parse(cardJson);
    const validation = card.validateProperties();
    if (validation.validationEvents.length > 0) {
      failures.push(`${name}: ${validation.validationEvents.map((event) => event.message).join("; ")}`);
    }
  } catch (error) {
    failures.push(`${name}: ${String(error)}`);
  }
}

if (failures.length > 0) {
  console.error(JSON.stringify({ ok: false, failures }, null, 2));
  process.exit(1);
}

console.log(JSON.stringify({ ok: true, adaptiveCardVersion: "1.5", cardCount: names.length }, null, 2));
