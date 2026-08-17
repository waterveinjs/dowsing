import * as WV from '@watervein/core';
import { performance } from 'perf_hooks';

const input = JSON.parse(process.argv[2] || '[]');
const nodeMap = new Map();
let hasError = false;
let errorMsg = '';
let totalFlushDurationMs = 0;

try {
  for (const op of input) {
    switch (op.type) {
      case 'createState':
        nodeMap.set(op.id, WV.createState(op.value));
        break;
      case 'createCompute':
        nodeMap.set(op.id, WV.createCompute(() => {
          return op.deps.reduce((acc, depId) => acc + WV.read(nodeMap.get(depId)), 0);
        }));
        break;
      case 'write':
        WV.write(nodeMap.get(op.id), op.value);
        break;
      case 'flush': {
        const start = performance.now();
        WV.flush();
        totalFlushDurationMs += (performance.now() - start);
        break;
      }
    }
  }

  
  const start = performance.now();
  WV.flush();
  totalFlushDurationMs += (performance.now() - start);

  
  const maxAllowedMs = 100 + input.length * 0.2;
  if (totalFlushDurationMs > maxAllowedMs) {
    hasError = true;
    errorMsg = `Performance anomaly: flush took ${totalFlushDurationMs.toFixed(2)}ms (threshold: ${maxAllowedMs.toFixed(2)}ms)`;
  }

} catch (e) {
  hasError = true;
  errorMsg = e.message;
}

const values = {};
for (const [id, node] of nodeMap.entries()) {
  values[String(id)] = node.value;
}

console.log(JSON.stringify({ 
  hasError, 
  errorMsg, 
  values, 
  flushDurationMs: totalFlushDurationMs 
}));