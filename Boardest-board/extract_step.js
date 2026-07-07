const fs = require('fs');
const readline = require('readline');

const logPath = "C:\\Users\\jiwho\\.gemini\\antigravity\\brain\\3d7742b4-3097-4558-9040-65f10e369b36\\.system_generated\\logs\\transcript.jsonl";
const outPath = "C:\\Users\\jiwho\\.gemini\\antigravity\\brain\\3d7742b4-3097-4558-9040-65f10e369b36\\scratch\\extracted_step_1186.txt";

async function main() {
  const fileStream = fs.createReadStream(logPath);
  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity
  });

  const outStream = fs.createWriteStream(outPath, { encoding: 'utf8' });

  for await (const line of rl) {
    const data = JSON.parse(line);
    if (data.step_index === 1186) {
      outStream.write(`=== STEP 1186 ===\n`);
      outStream.write(JSON.stringify(data, null, 2));
      break;
    }
  }
  outStream.end();
  console.log("Done extracting step 1186");
}

main().catch(err => console.error(err));
