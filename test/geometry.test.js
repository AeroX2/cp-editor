const assert = require('node:assert/strict');
const {
  Editor,
  VSVG,
  internalAngleBisector,
  rayToPageBoundary,
} = require('../cpedit.js');

const close = (actual, expected, message) => {
  assert.ok(Math.abs(actual - expected) < 1e-9,
    `${message}: expected ${expected}, received ${actual}`);
};

const direction = internalAngleBisector([0, 0], [1, 0], [0, 1]);
close(direction[0], Math.SQRT1_2, '45-degree bisector x');
close(direction[1], Math.SQRT1_2, '45-degree bisector y');

assert.equal(
  internalAngleBisector([0, 0], [1, 0], [-1, 0]),
  null,
  'A straight angle has no unique internal bisector',
);

const endpoint = rayToPageBoundary(
  [0, 0], direction, {xMin: 0, yMin: 0, xMax: 4, yMax: 2},
);
close(endpoint[0], 2, 'Bisector clips to the first page boundary x');
close(endpoint[1], 2, 'Bisector clips to the first page boundary y');

const editor = new Editor(new VSVG('svg'));
editor.setGridDivisions(2);
let snapped = editor.nearestFeature({x: 1.27, y: 2.74});
assert.deepEqual(snapped, {x: 1.5, y: 2.5}, 'Half-grid snapping');

editor.setGridDivisions(1);
editor.addCrease({x: 0, y: 0}, {x: 3, y: 1}, 'U', 0);
snapped = editor.nearestFeature({x: 1.48, y: 0.52});
assert.deepEqual(snapped, {x: 1.5, y: 0.5}, 'Edge-midpoint snapping');

editor.setSnapMidpoints(false);
snapped = editor.nearestFeature({x: 1.48, y: 0.52});
assert.deepEqual(snapped, {x: 1, y: 1}, 'Midpoint snapping can be disabled');

console.log('Geometry tests passed');
