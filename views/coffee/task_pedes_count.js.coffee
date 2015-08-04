do ($=jQuery) ->
  metas = document.getElementsByTagName('meta')
  params = {}

  # 矩形描画用のフィールド
  point1 = {}
  point2 = {}
  rects = []

  for meta in metas
    key = meta.getAttribute("name")
    val = meta.getAttribute("value")
    #console.log("#{key}: #{val}")
    params[key] = val

  DrawRect = (id,rect,layer_index,color,stroke_width) ->
    $(id).drawRect({
      layer:true,
      draggable: false,
      strokeStyle: color,
      strokeWidth: stroke_width,
      x: rect.x, y: rect.y,
      width: rect.width, height: rect.height,
      fromCenter: false,
      index:layer_index})



  # 入力中の矩形を描画する
  DrawFloatRect = (id,point1, point2, color) ->
    #console.log("DrawFloatRect")
    left = Math.min(point1.x, point2.x)
    top = Math.min(point1.y, point2.y)
    width = Math.abs(point1.x - point2.x)
    height = Math.abs(point1.y - point2.y)
    #console.log(id)
    #console.log(color)
    $(id).setLayer('float',{
      type: 'rectangle',
      layer: true,
      draggable: false,
      strokeStyle: color,#'#ff0000',
      strokeWidth: 1,
      x: left, y: top,
      width: width, height: height,
      fromCenter: false,
      visible: true
    }).drawLayers()



  DrawCanvas = (id, image_filepath,line_filepath)->
    image = new Image()
    image.src = params["src_imagepath"]
    line = new Image()
    line.src = params["line_imagepath"]

    #console.log($(id))
    #console.log(params["blob_path"])
    #console.log(params["line_imagepath"])

    $(id).clearCanvas()
    $(id).drawImage({
      layer: true,
      index:0,
      name: 'base_image',
      source: image,
      opacity:1.0,
      scale: 1.0,
      x: 0,
      y: 0,
      width: params['image_width'],
      height: params['image_height'],
      fromCenter: false
    })
    $(id).drawImage({
      layer: true,
      index:1,
      name: 'line_image',
      source: line,
      opacity:0.8,
      scale: 1.0,
      x: 0,
      y: 0,
      width: params['image_width'],
      height: params['image_height'],
      fromCenter: false
    }).drawLayers();
    $(id).addLayer({
      type: 'rectangle',
      layer: true,
      name: 'float',
      draggable: false,
      strokeStyle: '#ff0000',
      strokeWidth: 1,
      x: 0, y: 0,
      width: 50, height: 50,
      fromCenter: false,
      visible: false
    }).drawLayers()
    $(id).setLayer('float',{visible: false}).drawLayers()

  DrawFixedRect = (id,point1,point2,color) ->
    #console.log("DrawFixedRect")
    left = Math.min(point1.x, point2.x)
    top = Math.min(point1.y, point2.y)
    width = Math.abs(point1.x - point2.x)
    height = Math.abs(point1.y - point2.y)
    type = $(id).attr('type')
    rect = {'x':left,'y':top,'width':width,'height':height, 'type':type}
    point1 = {}
    point2 = {}
    $(id).setLayer('float',{visible:false})
    DrawRect(id,rect,3,'#ffffff',2)
    DrawRect(id,rect,4,color,1)
    $(id).drawText({
      fillStyle: color,     # 文字色（青）
      fontSize: 20,             # フォントサイズ（24px）
      fontFamily: "Arial",      # フォントファミリー（Arial）
      x: rect.x,                   # x方向位置（240px）
      y: rect.y,                   # y方向位置（120px）
      fromCenter: false,
      index: 5,
      layer:true,
      text: "通行人[#{rects.length+1}]"  # 文字文言
    })
    return rect

  Regist = (rect,is_left)->
    # rectを正規化
    rect.x /= params['image_width']
    rect.y /= params['image_height']
    rect.width /= params['image_width']
    rect.height /= params['image_height']
    # id,point1,point2を変数に保存する．
    rects.push(rect)
    # formの更新をする
    fieldset = $('#attributes_template fieldset').clone(true)
    id = "annotation-#{rects.length}"
    $(fieldset).attr('id',id)
    $(fieldset).find(".pedes_label").text("通行人[#{rects.length}]")

    gender = assign_gender(is_left)
    $(fieldset).find(".gender").attr('value',gender)

    rect_str = JSON.stringify(rect)
    $(fieldset).find(".rect").text(rect_str)
    $('#annotation_form').append(fieldset)
    canvasData = $('#canvas_current')[0].toDataURL()
    canvasData = canvasData.replace(/^data:image\/png;base64,/, '')
    $('#post_canvas').attr('value',canvasData)

  assign_color = (is_left) ->
    color = '#0000ff'            # 男性は青
    color = '#ff0000' if is_left # 女性は赤
    return color
  assign_gender = (is_left) ->
    return 'female' if is_left
    return 'male'

  makeCanvasClickable = (id) ->
    #console.log(id)
    $(id).on('contextmenu', (-> return false))
    $(id).mousedown (evt) ->
      rect = $(evt.target).offset()
      x = evt.pageX - rect.left
      y = evt.pageY - rect.top
      point1 = {x: x, y: y}
      $(this).attr('drawing','true')
      point2 = {x: x, y: y}
      color = assign_color(evt.which==1)
      DrawFloatRect(id,point1,point2,color)


    $(id).mouseup (evt) ->
      rect = $(evt.target).offset()
      x = evt.pageX - rect.left
      y = evt.pageY - rect.top
      point2 = {x: x, y: y}
      color = assign_color(evt.which==1)
      rect = DrawFixedRect(id,point1,point2,color)
      Regist(rect,evt.which==1)
      $(this).attr('drawing','false')

    $(id).mousemove (evt) ->
      if 'true' != ($(this).attr('drawing'))
        return
      rect = $(evt.target).offset()
      x = evt.pageX - rect.left
      y = evt.pageY - rect.top
      point2 = {x: x, y: y}
      color = assign_color(evt.which==1)
      DrawFloatRect(id,point1,point2,color)

  DrawCanvas('#canvas_current', params['blob_path'], params['line_filepath'])
  makeCanvasClickable('#canvas_current')

  AnnotationCheck = ->
    console.log('annotation_completion submit')
    return false
    $("#annotation_completion .direction").each (i,elem) =>
      if $(elem).attr('value') == "not set"
        console.log($(elem).attr('value'))
        alert("移動方向が入力されていないものがあります")
        return false
    return false

  $('.go_to_next').click = ->

  $('#annotation_completion').submit = ->
    alert("hoge")
    return false
    AnnotationCheck

  0
  #$('.reset_canvas').click ->
  #  reset_all()
  # スライドバー(スライダー)を作る

