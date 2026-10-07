import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const source=fs.readFileSync('chrome-extension/posting.js','utf8');
const start=source.indexOf('async function insertBodyText(');
const end=source.indexOf('async function waitFor(',start);
let result='', chunks=[];
const context=vm.createContext({
 command:async(method,{text})=>{assert.equal(method,'Input.insertText');assert.ok(!text.includes('\n'));chunks.push(text);result+=text;},
 key:async()=>{result+='\n';},delay:async()=>{}
});
vm.runInContext(source.slice(start,end),context);
const input='첫 문단\n\n📍 히츠노야 잠실점\n영업시간\n화~일 10:30~22:00\n\n#잠실맛집';
await vm.runInContext(`insertBodyText(${JSON.stringify(input)})`,context);
assert.equal(result,input);
assert.ok(chunks.includes('📍'));
console.log('Passed multiline, empty paragraph, emoji and trailing restaurant-info input preservation');
