import test from 'ava';
import scriptFunction from './index.js';

test('scriptFunction is defined and returns a value', t => {
    t.truthy(scriptFunction, 'scriptFunction should be defined');
    const result = scriptFunction();
    t.truthy(result, 'scriptFunction should return a value');
});