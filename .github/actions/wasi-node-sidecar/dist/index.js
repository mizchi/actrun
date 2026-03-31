const fs = require("node:fs");

const message = process.env.INPUT_MESSAGE || "default-message";
const outputPath = process.env.GITHUB_OUTPUT;

if (!outputPath) {
  throw new Error("GITHUB_OUTPUT is required");
}

fs.appendFileSync(outputPath, `result=${message}\n`);
console.log(`js:${message}`);
