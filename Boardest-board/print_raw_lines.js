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
      console.log("RAW lines in 1713 content:");
      const lines = data.content.split('\n');
      for (let i = 0; i < 20; i++) {
        console.log(`Line ${i}: [${lines[i]}]`);
      }
      break;
    }
  }
}

main().catch(err => console.error(err));
