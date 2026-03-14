const fs = require('fs');
const name = process.env.INPUT_NAME || 'World';
const greeting = `Hello, ${name}!`;
console.log(greeting);

// Set output via GITHUB_OUTPUT file
const outputFile = process.env.GITHUB_OUTPUT;
if (outputFile) {
  fs.appendFileSync(outputFile, `greeting=${greeting}\n`);
}
