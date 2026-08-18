import * as WV from '@watervein/core';

const input = JSON.parse(process.argv[2] || '[]');
const nodeMap = new Map();
const evalCounts = new Map();
let hasError = false;
let errorMsg = '';

try {
  for (const op of input) {
    switch (op.type) {
      case 'createState':
        nodeMap.set(op.id, WV.createState(op.value));
        break;

      case 'createDynamicCompute': {
        evalCounts.set(op.id, 0);
        const node = WV.createCompute(() => {
          evalCounts.set(op.id, (evalCounts.get(op.id) || 0) + 1);
          const cond = WV.read(nodeMap.get(op.conditionId));
          return cond !== 0
            ? WV.read(nodeMap.get(op.thenId))
            : WV.read(nodeMap.get(op.elseId));
        });
        nodeMap.set(op.id, node);
        break;
      }

      case 'write':
        WV.write(nodeMap.get(op.id), op.value);
        break;

      case 'flush':
        WV.flush();
        break;
    }
  }

  WV.flush();

} catch (e) {
  hasError = true;
  errorMsg = e.message;
}

const values = {};
for (const [id, node] of nodeMap.entries()) {
  values[String(id)] = node.value;
}

const evalCountsObj = {};
for (const [id, count] of evalCounts.entries()) {
  evalCountsObj[String(id)] = count;
}

console.log(JSON.stringify({
  hasError,
  errorMsg,
  values,
  evalCounts: evalCountsObj
}));