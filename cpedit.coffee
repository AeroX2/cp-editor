margin = 0.5
defaultPage = ->
  xMin: 0
  yMin: 0
  xMax: 4
  yMax: 4

FOLD = require 'fold'

normalizeVector = (vector) ->
  length = Math.hypot vector[0], vector[1]
  return null unless length > FOLD.geom.EPS
  [vector[0] / length, vector[1] / length]

internalAngleBisector = (vertex, arm1, arm2) ->
  first = normalizeVector [arm1[0] - vertex[0], arm1[1] - vertex[1]]
  second = normalizeVector [arm2[0] - vertex[0], arm2[1] - vertex[1]]
  return null unless first? and second?
  normalizeVector [first[0] + second[0], first[1] + second[1]]

rayToPageBoundary = (origin, direction, page) ->
  best = null
  for axis in [0, 1]
    continue unless Math.abs(direction[axis]) > FOLD.geom.EPS
    bounds = if axis == 0 then [page.xMin, page.xMax] else [page.yMin, page.yMax]
    other = 1 - axis
    otherMin = if other == 0 then page.xMin else page.yMin
    otherMax = if other == 0 then page.xMax else page.yMax
    for bound in bounds
      distance = (bound - origin[axis]) / direction[axis]
      continue unless distance > FOLD.geom.EPS
      point = [
        origin[0] + direction[0] * distance
        origin[1] + direction[1] * distance
      ]
      continue unless point[other] >= otherMin - FOLD.geom.EPS and
                      point[other] <= otherMax + FOLD.geom.EPS
      best = {distance, point} unless best? and best.distance <= distance
  best?.point

foldAngleToOpacity = (foldAngle, assignment) ->
  if assignment in ['M', 'V']
    Math.max 0.1, (Math.abs foldAngle ? 180) / 180
  else
    1

class Editor
  constructor: (@svg) ->
    @undoStack = []
    @redoStack = []
    @updateUndoStack()
    @fold =
      file_spec: 1.2
      file_creator: 'Crease Pattern Editor'
      file_classes: ['singleModel']
      frame_classes: ['creasePattern']
      vertices_coords: []
      edges_vertices: []
      edges_assignment: []
      edges_foldAngle: []
      "cpedit:page": defaultPage()
    @gridGroup = @svg.group()
    .addClass 'grid'
    @creaseGroup = @svg.group()
    .addClass 'crease'
    @creaseLine = {}
    @midpointGroup = @svg.group()
    .addClass 'midpoint'
    @vertexGroup = @svg.group()
    .addClass 'vertex'
    @vertexCircle = {}
    @dragGroup = @svg.group()
    .addClass 'drag'
    @gridDivisions = 1
    @snapMidpoints = true
    @updateGrid()

  updateGrid: ->
    # Call whenever page dimensions change
    page = @fold["cpedit:page"]
    document?.getElementById('width')?.innerHTML = page.xMax
    document?.getElementById('height')?.innerHTML = page.yMax
    @gridGroup.clear()
    xSteps = Math.round (page.xMax - page.xMin) * @gridDivisions
    ySteps = Math.round (page.yMax - page.yMin) * @gridDivisions
    for i in [0..xSteps]
      x = page.xMin + i / @gridDivisions
      line = @gridGroup.line x, page.yMin, x, page.yMax
      line.addClass 'major' if i % @gridDivisions == 0
    for i in [0..ySteps]
      y = page.yMin + i / @gridDivisions
      line = @gridGroup.line page.xMin, y, page.xMax, y
      line.addClass 'major' if i % @gridDivisions == 0
    @svg.viewbox page.xMin - margin, page.yMin - margin, page.xMax - page.xMin + 2*margin, page.yMax - page.yMin + 2*margin

  setGridDivisions: (divisions) ->
    divisions = parseInt divisions
    return unless divisions in [1, 2, 4, 8]
    @gridDivisions = divisions
    @updateGrid()

  setSnapMidpoints: (@snapMidpoints) ->
    @updateMidpoints()

  setToolHint: (hint) ->
    document?.getElementById('toolHint')?.textContent = hint

  nearestFeature: (pt) ->
    p = [pt.x, pt.y]
    page = @fold["cpedit:page"]
    closest =
      [
        Math.max page.xMin, Math.min page.xMax,
          Math.round(pt.x * @gridDivisions) / @gridDivisions
        Math.max page.yMin, Math.min page.yMax,
          Math.round(pt.y * @gridDivisions) / @gridDivisions
      ]
    closestDistance = FOLD.geom.dist closest, p
    v = FOLD.geom.closestIndex p, @fold.vertices_coords
    if v?
      vertex = @fold.vertices_coords[v]
      distance = FOLD.geom.dist vertex, p
      if distance < closestDistance
        closest = vertex
        closestDistance = distance
    if @snapMidpoints
      for vertices in @fold.edges_vertices
        continue unless vertices?[0]? and vertices?[1]?
        first = @fold.vertices_coords[vertices[0]]
        second = @fold.vertices_coords[vertices[1]]
        midpoint = [(first[0] + second[0]) / 2, (first[1] + second[1]) / 2]
        distance = FOLD.geom.dist midpoint, p
        if distance < closestDistance
          closest = midpoint
          closestDistance = distance
    x: closest[0]
    y: closest[1]

  setTitle: (title) ->
    @fold['file_title'] = title

  setMode: (mode) ->
    @mode?.exit @
    @mode = mode
    @mode.enter @
  setLineType: (@lineType) ->
  setAbsFoldAngle: (@absFoldAngle) ->
  getFoldAngle: ->
    if @lineType == 'V'
      @absFoldAngle
    else if @lineType == 'M'
      -@absFoldAngle
    else
      0
  escape: ->
    @mode?.escape? @

  addVertex: (v) ->
    [i, changedEdges] =
      FOLD.filter.addVertexAndSubdivide @fold, [v.x, v.y], FOLD.geom.EPS
    @drawVertex i if i == @fold.vertices_coords.length - 1  # new vertex
    @drawEdge e for e in changedEdges
    i
  addCrease: (p1, p2, assignment, foldAngle) ->
    p1 = @addVertex p1
    p2 = @addVertex p2
    newVertices = @fold.vertices_coords.length
    changedEdges = FOLD.filter.addEdgeAndSubdivide @fold, p1, p2, FOLD.geom.EPS
    for e in changedEdges[0]
      @fold.edges_assignment[e] = assignment
      @fold.edges_foldAngle[e] = foldAngle
    @drawEdge e for e in changedEdges[i] for i in [0, 1]
    @drawVertex v for v in [newVertices ... @fold.vertices_coords.length]
    @updateMidpoints()
    #console.log @fold
    #@loadFold @fold
  subdivide: ->
    FOLD.filter.collapseNearbyVertices @fold, FOLD.geom.EPS
    FOLD.filter.subdivideCrossingEdges_vertices @fold, FOLD.geom.EPS
    @loadFold @fold

  saveForUndo: ->
    @undoStack.push FOLD.convert.deepCopy @fold
    @redoStack = []
    @updateUndoStack()
  undo: ->
    return unless @undoStack.length
    @redoStack.push @fold
    @fold = @undoStack.pop()
    @loadFold @fold
    @updateUndoStack()
  redo: ->
    return unless @redoStack.length
    @undoStack.push @fold
    @fold = @redoStack.pop()
    @loadFold @fold
    @updateUndoStack()
  updateUndoStack: ->
    document?.getElementById('undo')?.disabled = (@undoStack.length == 0)
    document?.getElementById('redo')?.disabled = (@redoStack.length == 0)

  transform: (matrix, integerize = true) ->
    ###
    Main transforms we care about (reflection and 90-degree rotation) should
    preserve integrality of coordinates.  Force this when integerize is true.
    ###
    @saveForUndo()
    integers = (Number.isInteger(x) for x in coords \
                for coords in @fold.vertices_coords) if integerize
    FOLD.filter.transform @fold, matrix
    if integerize
      for ints, v in integers
        for int, i in ints when int
          @fold.vertices_coords[v][i] = Math.round @fold.vertices_coords[v][i]
    @loadFold @fold
  reflectX: ->
    {xMin, xMax} = @fold['cpedit:page']
    @transform FOLD.geom.matrixReflectAxis 0, 2, (xMin + xMax) / 2
  reflectY: ->
    {yMin, yMax} = @fold['cpedit:page']
    @transform FOLD.geom.matrixReflectAxis 1, 2, (yMin + yMax) / 2
  rotate90: (cw) ->
    {xMin, xMax, yMin, yMax} = @fold['cpedit:page']
    if cw
      angle = Math.PI/2
    else
      angle = -Math.PI/2
    @transform FOLD.geom.matrixRotate2D angle,
      [(xMin + xMax) / 2, (yMin + yMax) / 2]
  rotateCW: -> @rotate90 true
  rotateCCW: -> @rotate90 false
  translate: (dx, dy) ->
    @transform FOLD.geom.matrixTranslate [dx, dy]
  shiftL: -> @translate -1, 0
  shiftR: -> @translate +1, 0
  shiftU: -> @translate 0, -1
  shiftD: -> @translate 0, +1

  loadFold: (@fold) ->
    @fold.version = 1.2
    @mode?.exit @
    @drawVertices()
    @fold.edges_foldAngle ?=
      for assignment in @fold.edges_assignment
        switch assignment
          when 'V'
            180    # "The fold angle is positive for valley folds,"
          when 'M'
            -180   # "negative for mountain folds, and"
          else
            0      # "zero for flat, unassigned, and border folds"
    @drawEdges()
    @fold["cpedit:page"] ?=
      if @fold.vertices_coords?.length
        xMin: Math.min ...(v[0] for v in @fold.vertices_coords)
        yMin: Math.min ...(v[1] for v in @fold.vertices_coords)
        xMax: Math.max ...(v[0] for v in @fold.vertices_coords)
        yMax: Math.max ...(v[1] for v in @fold.vertices_coords)
      else
        defaultPage()
    @updateGrid()
    document?.getElementById('title').value = @fold.file_title ? ''
    @mode?.enter @
  drawVertices: ->
    @vertexGroup.clear()
    @drawVertex v for v in [0...@fold.vertices_coords.length]
  drawEdges: ->
    @creaseGroup.clear()
    @drawEdge e for e in [0...@fold.edges_vertices.length]
    @updateMidpoints()
  updateMidpoints: ->
    @midpointGroup.clear()
    return unless @snapMidpoints
    seen = {}
    for vertices in @fold.edges_vertices
      continue unless vertices?[0]? and vertices?[1]?
      first = @fold.vertices_coords[vertices[0]]
      second = @fold.vertices_coords[vertices[1]]
      midpoint = [(first[0] + second[0]) / 2, (first[1] + second[1]) / 2]
      key = "#{midpoint[0]},#{midpoint[1]}"
      continue if seen[key]
      seen[key] = true
      @midpointGroup.circle(0.12).center midpoint[0], midpoint[1]
  drawVertex: (v) ->
    @vertexCircle[v]?.remove()
    @vertexCircle[v] = @vertexGroup.circle 0.2
    .center ...(@fold.vertices_coords[v])
    .attr 'data-index', v
  drawEdge: (e) ->
    @creaseLine[e]?.remove()
    coords = (@fold.vertices_coords[v] for v in @fold.edges_vertices[e])
    @creaseLine[e] =
    l = @creaseGroup.line coords[0][0], coords[0][1], coords[1][0], coords[1][1]
    .addClass @fold.edges_assignment[e]
    .attr 'stroke-opacity',
      foldAngleToOpacity @fold.edges_foldAngle[e], @fold.edges_assignment[e]
    .attr 'data-index', e

  cleanup: ->
    # Check for vertices of degree 0, or of degree 2
    # where the two incident edges are parallel.
    # Consider vertices in decreasing order so that indices don't change.
    FOLD.convert.edges_vertices_to_vertices_edges_unsorted @fold
    for v in [@fold.vertices_coords.length-1 .. 0]
      if @fold.vertices_edges[v].length == 0
        FOLD.filter.removeVertex @fold, v
      else if @fold.vertices_edges[v].length == 2
        edges = @fold.vertices_edges[v]
        vectors =
          for edge in edges
            vertices = @fold.edges_vertices[edge]
            coords =
              for vertex in vertices
                @fold.vertices_coords[vertex]
            FOLD.geom.mul (FOLD.geom.unit FOLD.geom.sub coords[0], coords[1]),
              if vertices[0] == v then 1 else -1
        if (FOLD.geom.dot vectors[0], vectors[1]) <= -1 + FOLD.geom.EPS
          for otherV in @fold.edges_vertices[edges[1]]
            break unless v == otherV
          vertices = @fold.edges_vertices[edges[0]]
          for i in [0...2]
            if vertices[i] == v
              vertices[i] = otherV
          FOLD.filter.removeEdge @fold, edges[1]
          FOLD.filter.removeVertex @fold, v
          FOLD.convert.edges_vertices_to_vertices_edges_unsorted @fold
    delete @fold.vertices_edges
    @drawVertices()
    @drawEdges()

  convertToFold: (splitCuts, json = true) ->
    ## Add face structure to @fold
    fold = FOLD.convert.deepCopy @fold
    FOLD.convert.edges_vertices_to_vertices_edges_sorted fold
    fold.frame_classes = (c for c in fold.frame_classes ? [] \
      when c not in ['cuts', 'noCuts'])
    unless FOLD.filter.cutEdges(fold).length
      fold.frame_classes.push 'noCuts'
    else if splitCuts
      fold.frame_classes.push 'noCuts'
      FOLD.filter.splitCuts fold
      #console.log 'cut', fold
    else
      fold.frame_classes.push 'cuts'
    FOLD.convert.vertices_edges_to_faces_vertices_edges fold
    #console.log fold
    fold = FOLD.convert.toJSON fold if json
    fold
  downloadFold: ->
    #json = FOLD.convert.toJSON @fold  # minimal content
    @download @convertToFold(false), 'application/json', '.fold'
  downloadSplitFold: ->
    @download @convertToFold(true), 'application/json', '-split.fold'
  convertToSVG: (options) ->
    svg = @svg.clone()
    svg.find('.C').front()
    svg.find('.B').front()
    svg.find('.B').stroke color: '#000000'
    if options?.nice
      ## Cuts look the same as boundary, and are very thick (0.2).
      svg.find('.B, .C').stroke width: 0.2
      svg.find('.C').stroke color: '#000000'
      ## Nice blue/red, even in grayscale
      svg.find('.M').stroke color: '#ff6060'
      svg.find('.V').stroke color: '#385dcf'
      ## Instead of opacity, use thickness for bigger folds.
      ## 90 degrees has thickness 0.1, while 180 degrees has thickness 0.15.
      svg.find('.M, .V, .B, .C').each ->
        t = @attr 'stroke-opacity'
        @stroke width: (1-t) * 0.05 + t * 0.15
        @attr 'stroke-opacity', 1
    else
      svg.find('.M, .V, .B, .C').stroke width: 0.1
      svg.find('.C').stroke color: '#00ff00'
      svg.find('.M').stroke color: '#ff0000'
      svg.find('.V').stroke color: '#0000ff'
    unless options?.noUnfold
      svg.find('.U').stroke color: '#ffff00', width: 0.1
    svg.find('.vertex, .drag').remove()
    if options?.grid
      svg.find('.grid').stroke color: '#dddddd', width: 0.05
    else
      svg.find('.grid').remove()
    svg.attr 'width', "#{@svg.viewbox().width}cm"
    svg.attr 'height', "#{@svg.viewbox().height}cm"
    svg.element('style').words '''
      line { stroke-linecap: round; }
    '''
    svg.svg()
    .replace /[ ]id="[^"]+"/g, ''
  downloadSVG: ->
    @download @convertToSVG(), 'image/svg+xml', '.svg'
  download: (content, type, extension) ->
    a = document.getElementById 'download'
    a.href = url = URL.createObjectURL new Blob [content], {type}
    a.download = (@fold.file_title or 'creasepattern') + extension
    a.click()
    a.href = ''
    URL.revokeObjectURL url

class Mode

class LineDrawMode extends Mode
  enter: (editor) ->
    editor.setToolHint 'Draw crease · choose the first point'
    svg = editor.svg
    @which = 0 ## 0 = first point, 1 = second point
    @points = {}
    @circles = []
    @crease = @line = null
    @dragging = false
    svg.mousemove move = (e) =>
      point = editor.nearestFeature svg.point e.clientX, e.clientY
      ## Wait for distance threshold in drag before triggering drag
      if e.buttons
        if @down?
          unless point.x == @down.x and
                 point.y == @down.y
            @dragging = true
            @which = 1
        else if @down == null
          @down = point
      @points[@which] = point
      unless @which < @circles.length
        @circles.push editor.dragGroup.circle 0.3
      @circles[@which].center @points[@which].x, @points[@which].y
      if @which == 1
        @line ?= editor.dragGroup.line().addClass 'drag'
        @crease ?= editor.dragGroup.line().addClass editor.lineType
        .attr 'stroke-opacity',
          foldAngleToOpacity editor.getFoldAngle(), editor.lineType
        @line.plot @points[0].x, @points[0].y, @points[1].x, @points[1].y
        @crease.plot @points[0].x, @points[0].y, @points[1].x, @points[1].y
    svg.mousedown (e) =>
      @down = null # special value meaning 'set'
      move e
    svg.mouseup (e) =>
      move e
      ## Click, click style line drawing: advance to second point if not
      ## currently in drag mode, and didn't just @escape (no "down" point).
      if @which == 0 and not @dragging and @down != undefined
        @which = 1
        editor.setToolHint 'Draw crease · choose the second point'
      else
        ## Commit new crease, unless it's zero length.
        unless @which == 0 or (
          @points[0].x == @points[1].x and @points[0].y == @points[1].y
        )
          editor.saveForUndo()
          editor.addCrease @points[0], @points[1],
            editor.lineType, editor.getFoldAngle()
        @escape editor
        move e
    svg.mouseenter (e) =>
      ## Cancel crease if user exits, lets go of button, and re-enters
      @escape editor if @dragging and e.buttons == 0
      move e
    svg.mouseleave (e) =>
      if @circles.length == @which + 1
        @circles.pop().remove()
  escape: (editor) ->
    @circles.pop().remove() while @circles.length
    @crease?.remove()
    @line?.remove()
    @crease = @line = null
    @which = 0
    @dragging = false
    @down = undefined
    editor.setToolHint 'Draw crease · choose the first point'
  exit: (editor) ->
    @escape editor
    editor.svg
    .mousemove null
    .mousedown null
    .mouseup null
    .mouseenter null
    .mouseleave null

class AngleBisectorMode extends Mode
  enter: (editor) ->
    svg = editor.svg
    @points = []
    @fixedCircles = []
    @hoverCircle = editor.dragGroup.circle(0.3)
    @firstArm = @secondArm = @crease = null
    editor.setToolHint 'Bisect angle · choose the angle vertex'

    svg.mousemove move = (e) =>
      @hover = editor.nearestFeature svg.point e.clientX, e.clientY
      @hoverCircle.center @hover.x, @hover.y
      vertex = @points[0]
      if vertex?
        @firstArm ?= editor.dragGroup.line().addClass 'guide'
        firstEnd = @points[1] ? @hover
        @firstArm.plot vertex.x, vertex.y, firstEnd.x, firstEnd.y
      if @points.length == 2
        @secondArm ?= editor.dragGroup.line().addClass 'guide'
        @secondArm.plot vertex.x, vertex.y, @hover.x, @hover.y
        direction = internalAngleBisector(
          [vertex.x, vertex.y]
          [@points[1].x, @points[1].y]
          [@hover.x, @hover.y]
        )
        endpoint = rayToPageBoundary(
          [vertex.x, vertex.y], direction, editor.fold['cpedit:page']
        ) if direction?
        if endpoint?
          @crease ?= editor.dragGroup.line().addClass('bisector')
          @crease.addClass editor.lineType
          .attr 'stroke-opacity',
            foldAngleToOpacity editor.getFoldAngle(), editor.lineType
          @crease.plot vertex.x, vertex.y, endpoint[0], endpoint[1]
        else
          @crease?.remove()
          @crease = null

    svg.mouseup (e) =>
      move e
      if @points.length and @hover.x == @points[0].x and
                            @hover.y == @points[0].y
        editor.setToolHint 'Choose a point away from the angle vertex'
        return
      if @points.length == 2
        vertex = @points[0]
        direction = internalAngleBisector(
          [vertex.x, vertex.y]
          [@points[1].x, @points[1].y]
          [@hover.x, @hover.y]
        )
        endpoint = rayToPageBoundary(
          [vertex.x, vertex.y], direction, editor.fold['cpedit:page']
        ) if direction?
        unless endpoint?
          editor.setToolHint 'Those arms do not define an angle · choose another point'
          return
        editor.saveForUndo()
        editor.addCrease vertex, {x: endpoint[0], y: endpoint[1]},
          editor.lineType, editor.getFoldAngle()
        @reset editor
        return
      @points.push x: @hover.x, y: @hover.y
      @fixedCircles.push editor.dragGroup.circle(0.3)
      .center @hover.x, @hover.y
      if @points.length == 1
        editor.setToolHint 'Bisect angle · choose a point on the first arm'
      else
        editor.setToolHint 'Bisect angle · choose a point on the second arm'

    svg.mouseleave (e) =>
      @hoverCircle?.remove()
      @hoverCircle = null
    svg.mouseenter (e) =>
      @hoverCircle ?= editor.dragGroup.circle(0.3)
      move e

  reset: (editor) ->
    @fixedCircles.pop().remove() while @fixedCircles.length
    @firstArm?.remove()
    @secondArm?.remove()
    @crease?.remove()
    @firstArm = @secondArm = @crease = null
    @points = []
    editor.setToolHint 'Bisect angle · choose the angle vertex'

  escape: (editor) ->
    @reset editor

  exit: (editor) ->
    @reset editor
    @hoverCircle?.remove()
    @hoverCircle = null
    editor.svg
    .mousemove null
    .mouseup null
    .mouseenter null
    .mouseleave null

class LinePaintMode extends Mode
  enter: (editor) ->
    editor.setToolHint 'Paint over creases to change them'
    svg = editor.svg
    svg.mousedown change = (e) =>
      return unless e.buttons
      return unless e.target.tagName == 'line'
      edge = parseInt e.target.getAttribute 'data-index'
      return if isNaN edge
      @paint editor, edge
    svg.mouseover change  # painting
  exit: (editor) ->
    editor.svg
    .mousedown null
    .mouseover null

class LineAssignMode extends LinePaintMode
  paint: (editor, edge) ->
    unless editor.fold.edges_assignment[edge] == editor.lineType and
           editor.fold.edges_foldAngle[edge] == editor.getFoldAngle()
      editor.saveForUndo()
      editor.fold.edges_assignment[edge] = editor.lineType
      editor.fold.edges_foldAngle[edge] = editor.getFoldAngle()
      editor.drawEdge edge

class LineEraseMode extends LinePaintMode
  enter: (editor) ->
    super editor
    editor.setToolHint 'Paint over creases to erase them'
  paint: (editor, edge) ->
    editor.saveForUndo()
    vertices = editor.fold.edges_vertices[edge]
    FOLD.filter.removeEdge editor.fold, edge
    editor.drawEdges()
    # Remove any now-isolated vertices
    incident = {}
    for edgeVertices in editor.fold.edges_vertices
      for vertex in edgeVertices
        incident[vertex] = true
    # Remove vertices in decreasing order so that indices don't change
    if vertices[0] < vertices[1]
      vertices = [vertices[1], vertices[0]]
    for vertex in vertices
      unless incident[vertex]
        FOLD.filter.removeVertex editor.fold, vertex
        editor.drawVertices() # might get called twice

class VertexMoveMode extends Mode
  enter: (editor) ->
    editor.setToolHint 'Move vertex · drag an existing point'
    svg = editor.svg
    svg.mousemove move = (e) =>
      @point = editor.nearestFeature svg.point e.clientX, e.clientY
      if @vertex?
        @drag editor
    svg.mousedown (e) =>
      @vertex = parseInt e.target.getAttribute 'data-index'
      if e.target.tagName == 'circle' and @vertex?
        @circle = e.target.instance
        .addClass 'drag'
        @down = null # special value meaning 'set'
        move e
      else
        @circle = @vertex = null
    svg.mouseup (e) =>
      move e
      if @vertex?
        ## Commit new location
        unless @point.x == editor.fold.vertices_coords[@vertex][0] and
               @point.y == editor.fold.vertices_coords[@vertex][1]
          editor.saveForUndo()
          editor.fold.vertices_coords[@vertex][0] = @point.x
          editor.fold.vertices_coords[@vertex][1] = @point.y
          @vertex = null
          editor.subdivide()
          #editor.drawVertex @vertex
          #for vertices, edge in editor.fold.edges_vertices
          #  editor.drawEdge edge if @vertex in vertices
        @escape editor
    svg.mouseover (e) =>
      return if @vertex?
      return unless e.target.tagName == 'circle' and index = e.target.getAttribute 'data-index'
      e.target.instance.addClass 'drag'
    svg.mouseout (e) =>
      return unless e.target.tagName == 'circle' and e.target.getAttribute 'data-index'
      return if @vertex == parseInt e.target.getAttribute 'data-index'
      e.target.instance.removeClass 'drag'
    #svg.mouseenter (e) =>
    #  ## Cancel crease if user exits, lets go of button, and re-enters
    #  @escape editor if @dragging and e.buttons == 0
    #  move e
    #svg.mouseleave (e) =>
    #  if @circles.length == @which + 1
    #    @circles.pop().remove()
  escape: (editor) ->
    if @vertex?
      @circle.removeClass 'drag'
      @point =
        x: editor.fold.vertices_coords[@vertex][0]
        y: editor.fold.vertices_coords[@vertex][1]
      @drag editor
    @circle = @vertex = null
  exit: (editor) ->
    @escape editor
    editor.svg
    .find '.vertex circle.drag'
    .removeClass 'drag'
    editor.svg
    .mousemove null
    .mousedown null
    .mouseup null
    .mouseenter null
    .mouseleave null
  drag: (editor) ->
    @circle.center @point.x, @point.y
    vertex = @vertex
    point = @point
    editor.svg.find '.crease line'
    .each ->
      edge = @attr 'data-index'
      i = editor.fold.edges_vertices[edge].indexOf vertex
      if i >= 0
        @attr "x#{i+1}", point.x
        @attr "y#{i+1}", point.y

modes =
  drawLine: new LineDrawMode
  angleBisector: new AngleBisectorMode
  assignLine: new LineAssignMode
  eraseLine: new LineEraseMode
  moveVertex: new VertexMoveMode

window?.onload = ->
  svg = SVG().addTo '#interface'
  editor = new Editor svg
  for input in document.getElementsByTagName 'input'
    do (input) ->
      switch input.getAttribute 'name'
        when 'mode'
          if input.checked
            editor.setMode modes[input.id]
          input.addEventListener 'change', (e) ->
            return unless input.checked
            if input.id of modes
              editor.setMode modes[input.id]
            else
              console.warn "Unrecognized mode #{input.id}"
        when 'line'
          if input.checked
            editor.setLineType input.value
          input.addEventListener 'change', (e) ->
            return unless input.checked
            editor.setLineType input.value
      input.parentElement.addEventListener 'click', (e) ->
        unless e.target == input or e.target.tagName in ['LABEL', 'INPUT', 'A']
          input.click()
  window.addEventListener 'keyup', (e) =>
    switch e.key
      when 'd', 'D'
        document.getElementById('drawLine').click()
      when 'a', 'A'
        document.getElementById('assignLine').click()
      when 'i', 'I'
        document.getElementById('angleBisector').click()
      when 'e', 'E'
        document.getElementById('eraseLine').click()
      when 'm'
        document.getElementById('moveVertex').click()
      when 'b', 'B'
        document.getElementById('boundary').click()
      when 'M'
        document.getElementById('mountain').click()
      when 'V'
        document.getElementById('valley').click()
      when 'u', 'U'
        document.getElementById('unfolded').click()
      when 'c', 'C'
        document.getElementById('cut').click()
      when 'Escape'
        editor.escape()
      when 'z'
        editor.undo()
      when 'y', 'Z'
        editor.redo()
  for id in ['cleanup', 'undo', 'redo', 'reflectX', 'reflectY', 'rotateCCW', 'rotateCW', 'shiftL', 'shiftD', 'shiftU', 'shiftR']
    do (id) ->
      document.getElementById(id).addEventListener 'click', (e) ->
        e.stopPropagation()
        editor[id]()
  document.getElementById('loadFold').addEventListener 'click', (e) ->
    e.stopPropagation()
    document.getElementById('fileFold').click()
  document.getElementById('fileFold').addEventListener 'input', (e) ->
    e.stopPropagation()
    return unless e.target.files.length
    file = e.target.files[0]
    reader = new FileReader
    reader.onload = ->
      editor.loadFold JSON.parse reader.result
    reader.readAsText file
  document.getElementById('downloadFold').addEventListener 'click', (e) ->
    e.stopPropagation()
    editor.downloadFold()
  document.getElementById('downloadSplitFold').addEventListener 'click', (e) ->
    e.stopPropagation()
    editor.downloadSplitFold()
  document.getElementById('downloadSVG').addEventListener 'click', (e) ->
    e.preventDefault()
    e.stopPropagation()
    editor.downloadSVG()
  for [size, dim] in [['width', 'x'], ['height', 'y']]
    for [delta, op] in [[-1, 'Dec'], [+1, 'Inc']]
      do (size, dim, delta, op) ->
        document.getElementById(size+op).addEventListener 'click', (e) ->
          e.stopPropagation()
          editor.saveForUndo()
          editor.fold["cpedit:page"][dim + 'Max'] += delta
          editor.updateGrid()
  document.getElementById('title').addEventListener 'input', (e) ->
    editor.setTitle document.getElementById('title').value
  document.getElementById('gridDivisions').addEventListener 'change', (e) ->
    editor.setGridDivisions e.target.value
  document.getElementById('snapMidpoints').addEventListener 'change', (e) ->
    editor.setSnapMidpoints e.target.checked
  ## Fold angle
  angleInput = document.getElementById 'angle'
  angle = null
  setAngle = (value) ->
    return unless typeof value == 'number'
    return if isNaN value
    angle = value
    angle = Math.max angle, 0
    angle = Math.min angle, 180
    angleInput.value = angle
    editor.setAbsFoldAngle angle
  setAngle parseFloat angleInput.value  # initial value
  angleInput.addEventListener 'change', (e) ->
    setAngle eval angleInput.value  # allow formulas via eval
  for [sign, op] in [[+1, 'Add'], [-1, 'Sub']]
    for amt in [1, 90]
      document.getElementById("angle#{op}#{amt}").addEventListener 'click',
        do (sign, amt) -> (e) ->
          setAngle angle + sign * amt
  ## Origami Simulator
  simulator = null
  ready = false
  onReady = null
  checkReady = ->
    if ready
      onReady?()
      onReady = null
  window.addEventListener 'message', (e) ->
    if e.data and e.data.from == 'OrigamiSimulator' and e.data.status == 'ready'
      ready = true
      checkReady()
  document.getElementById('simulate').addEventListener 'click', (e) ->
    if simulator? and not simulator.closed
      simulator.focus()
    else
      ready = false
      #simulator = window.open 'OrigamiSimulator/?model=', 'simulator'
      simulator = window.open 'https://origamisimulator.org/?model=', 'simulator'
    fold = editor.convertToFold true, false  # split cuts, no JSON
    ## Origami Simulator wants 'F' for unfolded (facet) creases;
    ## it uses 'U' for undriven creases. :-/
    fold.edges_assignment =
      for assignment in fold.edges_assignment
        if assignment == 'U'
          'F'
        else
          assignment
    onReady = -> simulator.postMessage
      op: 'importFold'
      fold: fold
    , '*'
    checkReady()

## CLI

## VDOM simulation of used subset of svg.js interface
class VSVG
  constructor: (@tag, @parent) ->
    @classes = new Set
    @attrs = new Map
    @children = []
  svg: ->
    s = ''
    if @tag == 'svg'
      s += '''
        <?xml version="1.0" encoding="utf-8"?>

      '''
      @attrs.set 'xmlns', 'http://www.w3.org/2000/svg'
    if @classes.size
      @attrs.set 'class', (c for c from @classes).join ' '
    else
      @attrs.delete 'class'
    s += "<#{@tag}"
    for [key, value] from @attrs
      s += " #{key}=\"#{value}\""
    if @innerHTML
      s + ">\n" + @innerHTML + "\n</#{@tag}>"
    else if @children.length
      s + ">\n" + (
        for child in @children when not child.removed
          child.svg()
      ).join("\n") +
      "\n</#{@tag}>"
    else
      s + "/>"
  remove: ->
    @removed = true
    @
  clear: ->
    child.parent = undefined for child in @children
    @children = []
    @
  attr: (key, value) ->
    if value?  # setter
      @attrs.set key, value
      @
    else  # getter
      @attrs.get key
  viewbox: (x, y, width, height) ->
    if x?  # setter
      @attr 'viewBox', "#{x} #{y} #{width} #{height}"
    else  # getter
      coords = @attr 'viewBox'
      .split /\s+/
      .map parseFloat
      x: coords[0]
      y: coords[1]
      width: coords[2]
      height: coords[3]
  addClass: (c) ->
    @classes.add c
    @
  group: ->
    @children.push child = new VSVG 'g', @
    child
  line: (x1, y1, x2, y2) ->
    @children.push child = new VSVG 'line', @
    child
    .attr 'x1', x1
    .attr 'y1', y1
    .attr 'x2', x2
    .attr 'y2', y2
  stroke: ({color, width}) ->
    @attr 'stroke', color if color?
    @attr 'stroke-width', width if width?
    @
  circle: (diameter) ->
    @children.push child = new VSVG 'circle', @
    child.attr 'r', diameter / 2
  center: (x, y) ->
    console.assert @tag == 'circle'
    @attr 'cx', x
    .attr 'cy', y
  front: ->
    i = @parent.children.indexOf @
    console.assert i >= 0
    @parent.children.splice i, 1
    @parent.children.push @
    @
  element: (tag) ->
    @children.push child = new VSVG tag, @
    child
  words: (child) ->
    @innerHTML = child
    @
  clone: ->
    # Ignore clone operation because we're not rendering to DOM
    @
  find: (pattern) ->
    classes =
      for part in pattern.split /\s*,\s*/
        match = part.match /^\.([^.]+)$/
        throw new Error "Bad select pattern '#{part}'" unless match?
        match[1]
    results = []
    results.each = (f) -> f.call node for node in @
    for shortcut in ['stroke', 'remove', 'front']
      do (shortcut) ->
        results[shortcut] = (...args) ->
          for node in results
            node[shortcut](...args)
    recurse = (node) ->
      match = false
      for class_ in classes
        if node.classes.has class_
          match = true
          break
      results.push node if match
      for child in node.children when not child.removed
        recurse child
      return
    recurse @
    results

cli = (args = process.argv[2..]) ->
  fs = require 'fs'
  unless args.length
    console.log """
      Usage: coffee cpedit.coffee [formats/options] file1.fold file2.fold ...
      Formats:
        -s/--svg   .svg
        -f/--fold  .fold
      Options:
        -c/--cleanup    Remove unnecessary degree-0 and -2 vertices
        -g/--grid       Keep grid lines
        -u/--no-unfold  Don't color unfolded creases yellow
        -n/--nice       Nice colors instead of pure RGB for Origami Simulator
    """
  formats = []
  cpFiles = []
  cleanup = false
  options = {}
  for arg in args
    switch arg
      when '-c', '--clean', '--cleanup'
        cleanup = true
      when '-s', '--svg'
        formats.push 'SVG'
      when '-f', '--fold'
        formats.push 'Fold'
      when '-u', '--no-unfold'
        options.noUnfold = true
      when '-g', '--grid'
        options.grid = true
      when '-n', '--nice'
        options.nice = true
      else
        if arg.startsWith '-'
          console.log "Unknown option: #{arg}"
          continue
        cpFiles.push arg
  for cpFile in cpFiles
    editor = new Editor new VSVG 'svg'
    cpData = JSON.parse fs.readFileSync cpFile, encoding: 'utf8'
    editor.loadFold cpData
    editor.cleanup() if cleanup
    for format in formats
      output = editor["convertTo#{format}"] options
      outputPath = cpFile.replace /(\.(fold|cp))?$/, ".#{format.toLowerCase()}"
      fs.writeFileSync outputPath, output, encoding: 'utf8'

module?.exports = {
  Editor
  VSVG
  internalAngleBisector
  rayToPageBoundary
}

cli() if module? and require?.main == module
