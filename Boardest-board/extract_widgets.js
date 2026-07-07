const fs = require('fs');
const readline = require('readline');

const logPath = "C:\\Users\\jiwho\\.gemini\\antigravity\\brain\\3d7742b4-3097-4558-9040-65f10e369b36\\.system_generated\\logs\\transcript.jsonl";

async function main() {
  const fileStream = fs.createReadStream(logPath);
  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity
  });

  const methods = [
    '_buildStep1SchoolSearch',
    '_buildStep2GradeClass',
    '_buildStep3TimeSettings',
    '_buildStep4Textbooks'
  ];

  const foundDefinitions = {};
  for (const m of methods) {
    foundDefinitions[m] = [];
  }

  for await (const line of rl) {
    const data = JSON.parse(line);
    const text = JSON.stringify(data);
    for (const m of methods) {
      if (text.includes(m)) {
        // Let's store the step index and where we found it.
        foundDefinitions[m].push({
          step: data.step_index,
          type: data.type,
          source: data.source,
          length: text.length
        });
      }
    }
  }

  for (const m of methods) {
    console.log(`Method ${m} found in steps:`);
    console.log(foundDefinitions[m]);
  }
}

main().catch(err => console.error(err));
