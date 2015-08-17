do ($=jQuery) ->
  metas = document.getElementsByTagName('meta')
  params = {}

  # 矩形描画用のフィールド
  point1 = {}
  point2 = {}

  for meta in metas
    key = meta.getAttribute("name")
    val = meta.getAttribute("value")
    params[key] = val

  params["img_path"] = JSON.parse(params["img_path"])
  params['frame_begin'] = Number(params['frame_begin'])
  params['frame_end'] = Number(params['frame_end'])
  params['image_width'] = parseFloat(params['image_width'])
  params['image_height'] = parseFloat(params['image_height'])
  params['timestamp'] = JSON.parse(params['timestamp'])

  rects = new Array(params['frame_end']-params['frame_begin'])
  for i in [0...params['frame_end']-params['frame_begin']]
    rects[i] =[]


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
    console.log("DrawCanvas")
    console.log($(id))
    console.log(image_filepath)
    console.log(line_filepath)
    image = new Image()
    image.src = image_filepath
    line = new Image()
    line.src = line_filepath

    console.log($(id).attr('class'))
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

  DrawFixedRect = (id,point1,point2,color,frame,pedes_id) ->
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
      text: "通行人[#{pedes_id+1}]"
      # 文字文言
    })
    return rect

  Unregist = (obj, frame) ->
    pedes_id = Number($(obj).attr('data-pedes_id'))
    console.log("Unregist[#{frame}][#{pedes_id}]")
    local_rects = rects[frame-params['frame_begin']]
    local_rects.splice(pedes_id,1)
    id = "#annotation-#{frame}-#{pedes_id}"
    $(id).remove()

    #削除されたものより後ろの要素の整合性を取る
    for i in [pedes_id..local_rects.length]
      id = "annotation-#{frame}-#{i+1}" # 一つ削除されているから+1
      new_id = "annotation-#{frame}-#{i}"
      $('#'+id).attr('id',new_id)
      $('#'+new_id).find(".pedes_label").text("通行人[#{i+1}]")
      delete_button = $('#'+new_id).find(".delete")
      delete_button.attr('data-pedes_id',i)
      console.log("result of iteration: #{i}")
      console.log($('#'+id).length)
      console.log($('#'+id))
      console.log($('#'+new_id))

    # レイヤーの削除
    canvas = $("#canvas_current_#{frame}")
    for i in [0...local_rects.length+1]
      canvas.removeLayer(5)
      canvas.removeLayer(4)
      canvas.removeLayer(3)
      canvas.drawLayers()
    # 再描画
    for i in [0...local_rects.length]
      id = "#annotation-#{frame}-#{i}"
      color = assign_color($(id).find('.gender').attr('value'))
      point1 = {x: local_rects[i].x*params['image_width'], y: local_rects[i].y*params['image_height']}
      point2 = {x: point1.x+local_rects[i].width*params['image_width'], y: point1.y + local_rects[i].height*params['image_height']}
      DrawFixedRect(canvas,point1,point2,color,frame,i)

  Regist = (rect,is_left,frame)->
    # rectを正規化
    rect.x /= params['image_width']
    rect.y /= params['image_height']
    rect.width /= params['image_width']
    rect.height /= params['image_height']
    # id,point1,point2を変数に保存する．
    local_index = frame - params['frame_begin']

    rect_index = rects[local_index].length
    console.log(rect_index)
    rects[local_index].push(rect)
    # formの更新をする
    fieldset = $('#attributes_template fieldset').clone(true)
    id = "annotation-#{frame}-#{rect_index}"
    $(fieldset).attr('id',id)
    $(fieldset).find(".frame").attr('value',frame)
    $(fieldset).find(".pedes_label").text("通行人[#{rects[local_index].length}]")
    $(fieldset).find(".timestamp").attr('value',params['timestamp'][local_index])

    gender = assign_gender(is_left)
    $(fieldset).find(".gender").attr('value',gender)

    rect_str = JSON.stringify(rect)
    $(fieldset).find(".rect").text(rect_str)
    $(fieldset).find(".delete").attr("data-pedes_id",rect_index)
    delete_button = $(fieldset).find(".delete")
    delete_button.click ->
      Unregist(this,frame)

    $("#annotation_form_#{frame}").append(fieldset)

    #canvasData = $("#canvas_current_#{frame}")[0].toDataURL()
    #canvasData = canvasData.replace(/^data:image\/png;base64,/, '')
    #$("#post_canvas_#{frame}").attr('value',canvasData)

  assign_color = (gender) ->
    color = '#0000ff'                     # 男性は青
    color = '#ff0000' if gender=='female' # 女性は赤
    return color
  assign_gender = (is_left) ->
    return 'female' if is_left
    return 'male'

  makeCanvasClickable = (id,frame) ->
    #console.log(id)
    $(id).on('contextmenu', (-> return false))
    $(id).mousedown (evt) ->
      rect = $(evt.target).offset()
      x = evt.pageX - rect.left
      y = evt.pageY - rect.top
      point1 = {x: x, y: y}
      $(this).attr('drawing','true')
      point2 = {x: x, y: y}
      color = assign_color(assign_gender(evt.which==1))
      DrawFloatRect(id,point1,point2,color)


    $(id).mouseup (evt) ->
      rect = $(evt.target).offset()
      x = evt.pageX - rect.left
      y = evt.pageY - rect.top
      point2 = {x: x, y: y}
      color = assign_color(assign_gender(evt.which==1))
      $(this).attr('drawing','false')
      if point1.x == x or point2.x == y
        return
      rect = DrawFixedRect(id,point1,point2,color,frame,rects[frame-params['frame_begin']].length)
      Regist(rect,evt.which==1,frame)

    $(id).mousemove (evt) ->
      if 'true' != ($(this).attr('drawing'))
        return
      rect = $(evt.target).offset()
      x = evt.pageX - rect.left
      y = evt.pageY - rect.top
      point2 = {x: x, y: y}
      color = assign_color(assign_gender(evt.which==1))
      DrawFloatRect(id,point1,point2,color)

  offset = Number(params['frame_begin'])
  for i in [0..(Number(params['frame_end'])-offset-1)]
    console.log(i)
    DrawCanvas("#canvas_current_#{i+offset}", "#{params['imagepath_header']}/#{params['img_path'][i]}", params['line_imagepath'])
    makeCanvasClickable("#canvas_current_#{i+offset}",(i+offset))

  prev_segment = $(".prev_segment")
  if prev_segment.length > 0
    $('html, body').animate({scrollTop: prev_segment.offset().top}, 0)
    $('html, body').animate({scrollTop: $(".focus").offset().top-50}, 1000)
  jQuery("#annotation_completion").validationEngine();

  DrawNonfocusRects = (frame) ->
    return if !(params["img_path_#{frame}"])
    console.log($("#meta-img_path_#{frame}"))

    DrawCanvas("#canvas_nonfocus_#{frame}", params["img_path_#{frame}"],params['line_imagepath'])
    pedestrians = JSON.parse(params["pedestrians_#{frame}"])
    pedes_id = 0
    console.log(pedestrians)
    for ped in pedestrians
      color = assign_color(ped['gender'])
      _point1 = {
        x: ped['rect']['x'] * params['image_width'],
        y: ped['rect']['y'] * params['image_height']
      }
      _point2 = {
        x: _point1.x + ped['rect']['width'] * params['image_width'],
        y: _point1.y + ped['rect']['height']* params['image_height']}
      DrawFixedRect("#canvas_nonfocus_#{frame}",_point1,_point2,color,frame,pedes_id)
      pedes_id++

  for i in [0..Number(params['pre_frame_num'])]
    frame = offset - i
    break if frame < 0
    DrawNonfocusRects(frame)

  for i in [0..Number(params['post_frame_num'])]
    frame = params['frame_end'] + i
    DrawNonfocusRects(frame)

  # 作る!!
  Jump2task = (id) ->
    # form (id=annotation_complete)の内容を/annotationにポストする
    # これに加えて，以下のパラメタを追加する
    # <input type="hidden" name="jump" value="#{id}">

  #AnnotationCheck = ->
  #  console.log('annotation_completion submit')
  #  return false
  #  $("#annotation_completion .direction").each (i,elem) =>
  #    if $(elem).attr('value') == "not set"
  #      console.log($(elem).attr('value'))
  #      alert("移動方向が入力されていないものがあります")
  #      return false
  #  return false


  #$('#annotation_completion').submit = ->
  #  alert("hoge")
  #  AnnotationCheck
  #  return false

  0
  #$('.reset_canvas').click ->
  #  reset_all()
  # スライドバー(スライダー)を作る

