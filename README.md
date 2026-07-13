# Crease Pattern Editor

This is a draft of a web software tool for drawing quick crease/slit patterns.
It supports both integer-grid drawing and common geometric construction points.

## Features So Far

* **Graph-based**: Always maintain a planar graph, automatically subdividing
  and merging together touching vertices
* **Draw a crease** with two clicks or with dragging
* **Recolor** existing creases as different types by dragging over them
  (easily recoloring just part of a line)
* **Fold angle** support: enter degrees (or formula for degrees)
  to adjust mountain/valley fold amount (drawn via opacity)
* **Erase** existing creases by dragging over them
* **Move vertices** by dragging them (bringing all connected edges with them)
* **Snapping** to grid or existing vertex (e.g. from intersection)
* **Fractional grids** with whole, half, quarter, and eighth-unit snapping
* **Edge-midpoint snapping** with visible construction markers
* **Angle bisectors**: choose the vertex and two arms to construct the internal
  half-angle crease out to the paper boundary
* **Cleanup** to remove extra degree-0 or -2 vertices
* **Undo/redo**
* **Save/export** to .fold/.svg, including cutting (unwelding) of slits
* **CLI** for bulk conversion: `node cpedit.js --cleanup --fold --svg filename.cp`
* **Title** setting for document (`file_title` in fold format)
* **Page size** setting (width and height)
* **Transform** document by reflection or 90&deg; rotation
* **Keyboard shortcuts**:
  * Escape key cancels current operation
  * `z` for undo, `Z` or `y` for redo
  * Modes and line types list their key shortcut

## Construction tools

Choose a fractional **Grid step** when a model needs half- or quarter-unit
reference points. With **Snap to edge midpoints** enabled, every existing edge
offers its midpoint as a snap target; drawing to one automatically subdivides
that edge and creates a real FOLD vertex.

To halve an angle, choose **Bisect Angle** (or press `i`), then select:

1. The angle vertex
2. A point on the first arm
3. A point on the second arm

The editor previews and creates the internal angle bisector, clipped to the
paper boundary, using the currently selected crease assignment and fold angle.

## Installation
* Type `npm install` to do the necessary preparation
* Type `git submodule update --init --recursive` to use Origami Simulator integration
* Open `cpedit.html` in a web browser such as Chrome
