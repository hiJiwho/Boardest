const fs = require('fs');
const readline = require('readline');

const logPath = "C:\\Users\\jiwho\\.gemini\\antigravity\\brain\\3d7742b4-3097-4558-9040-65f10e369b36\\.system_generated\\logs\\transcript.jsonl";

async function main() {
  const fileStream = fs.createReadStream(logPath);
  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity
  });

  for await (const line of rl) {
    const data = JSON.parse(line);
    if (data.step_index === 1713) {
      const lines = data.content.split('\n');
      let matchedCount = 0;
      let failedCount = 0;
      for (const l of lines) {
        // Strip carriage return just in case
        const cleanL = l.replace(/\r/g, '');
        const match = cleanL.match(/^(\d+): (.*)$/);
        if (match) {
          matchedCount++;
          if (matchedCount <= 5) {
            console.log(`Matched: num=${match[1]}, content=[${match[2]}]`);
          }
        } else {
          failedCount++;
          if (failedCount <= 5) {
            console.log(`Failed: [${l}]`);
          }
        }
      }
      console.log(`Step 1713: Matched = ${matchedCount}, Failed = ${failedCount}`);
      break;
    }
  }
}

main().catch(err => console.error(err));
