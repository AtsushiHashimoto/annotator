jQuery(function ($) {
			 var point1 = {};
			 var point2 = {};
			 var rects = [];
			 var diff_image_path;
			 var mask_image_path;
			 var img_src_before;
			 var img_src_after;
			 var image_width;
			 var image_height;

			 
			 
			 var load_meta_data = function(){
				img_src_before = '/blob_images' + $('#meta-before_image').attr('value');
				img_src_after = '/blob_images' + $('#meta-after_image').attr('value');
				diff_image_path = '/blob_images' + $('#meta-diff_image').attr('value');
				mask_image_path = '/blob_images' + $('#meta-mask_image').attr('value');
				image_width = $('#meta-image_width').attr('value');
				image_height = $('#meta-image_height').attr('value');
				var is_put = $('#meta-put').attr('value')
				if(typeof is_put != typeof undefined) {
					type = 'put';
				}
				else{
					type = 'taken';
				}
			 
			 }
			 
			 var DrawRect = function(id,rect, layer_index,color,stroke_width){
					$(id).drawRect({
												 layer:true,
												 draggable: false,
												 strokeStyle: color,
												 strokeWidth: stroke_width,
												 x: rect.x, y: rect.y,
												 width: rect.width, height: rect.height,
												 fromCenter: false,
												 index:layer_index												 
												 });
			 };

			 // 選択済みの矩形を描画する
			 var DrawFixedRect = function(id,rect){
				$('canvas').each(function(index,elem){
												 DrawRect(elem,rect,3,'#ffffff',2);
												 DrawRect(elem,rect,4,'#a0ff00',1);
												 });
			  
			 };
			 var DrawFixedRectAndRegist = function(id,point1,point2){
				 var left = Math.min(point1.x, point2.x);
				 var top = Math.min(point1.y, point2.y);
				 var width = Math.abs(point1.x - point2.x);
				 var height = Math.abs(point1.y - point2.y);
				 var type = $(id).attr('type');
				 rect = {'x':left,'y':top,'width':width,'height':height, 'type':type};
				 point1 = {};
				 point2 = {};
				 // id,point1,point2を変数に保存する．
				 rects.push(rect);
				 // formの更新をする
				 $('#annotation').val(JSON.stringify(rects));
				$(id).setLayer('float',{visible:false});


				 return DrawFixedRect(id,rect);
			 }


			 var DrawFloatRect = function(id,rect2){
				var left = Math.min(point1.x, point2.x);
				var top = Math.min(point1.y, point2.y);
				var width = Math.abs(point1.x - point2.x);
				var height = Math.abs(point1.y - point2.y);
				rect = {'x':left,'y':top,'width':width,'height':height, 'type':type};
				$(id).setLayer('float',{
											 type: 'rectangle',
											 layer: true,
											 draggable: false,
											 strokeStyle: '#ff0000',
											 strokeWidth: 1,
											 x: left, y: top,
											 width: width, height: height,
											 fromCenter: false,
											 visible: true
											}).drawLayers();
			  };
			 
			  var brend = function(e,ui){
					$('canvas').each(function(index,elem){
														$(elem).setLayer('base_image',{opacity: ui.value}).drawLayers();
														 var opacity_value = 1.0 - ui.value;
														 $(elem).setLayer('diff_image',{opacity: opacity_value}).drawLayers();
														 
														});
			 
			  };
			 
				var maskCanvas = function(do_mask){
					$('canvas').each(function(index,elem){
													 $(elem).setLayer('mask',{visible:do_mask}).drawLayers();
												});
				};

			  var initCanvas = function(id,img_path){
				 $(id).clearCanvas();
				 $(id).drawImage({
												 layer: true,
												 index:0,
												 name: 'base_image',
												 source: img_path,
												 opacity:1.0,
												 scale: 1.0,
												 x: 0,
												 y: 0,
												 width: image_width,
												 height: image_height,
												 fromCenter: false
												 });
				 $(id).drawImage({
												 layer: true,
												 index:1,
												 name: 'diff_image',
												 source: diff_image_path,
												 opacity:0.0,
												 scale: 1.0,
												 x: 0,
												 y: 0,
												 width: image_width,
												 height: image_height,
												 fromCenter: false											
												 });
				$('canvas').each(function(index,elem){
												 $(elem).drawImage({
													source:mask_image_path,
													layer:true,
													name:'mask',
													index:2,
													x:0,y:0,
													width:image_width,
													height:image_height,
													fromCenter: false,
													compositing:'darker',
													visible: false
																					 });});
			 
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
											}).drawLayers();
				$(id).setLayer('float',{visible: false}).drawLayers();
				
				console.log(rects.length);
				rects.forEach(function(rect){
											console.log(rect);
											DrawFixedRect(id,rect);
											});
			 }
			 
			 var makeCanvasClickable = function(id){
					$(id).mousedown(function myMouseDown(evt) {
													var rect = $(evt.target).offset();
													var x = evt.pageX - rect.left;
													var y = evt.pageY - rect.top;
													point1 = {x: x, y: y};
													$(this).attr('drawing','true');
													});
					$(id).mouseup(function myMouseUp(evt){ 
												var rect = $(evt.target).offset();
												var x = evt.pageX - rect.left;
												var y = evt.pageY - rect.top;
												point2 = {x: x, y: y};
												DrawFixedRectAndRegist(id,point1,point2);
												$(this).attr('drawing','false');
												});
					$(id).mousemove(function myMouseOver(evt){
													if('true' != ($(this).attr('drawing'))){
														return;
													}
													var rect = $(evt.target).offset();
													var x = evt.pageX - rect.left;
													var y = evt.pageY - rect.top;
													point2 = {x: x, y: y};
													DrawFloatRect(id,point1,point2);
												});
			 };
			 
			 
			 var reset_canvas = function(){			 
				 $('canvas').removeLayers();
				 initCanvas('#img-before', img_src_before);
				 initCanvas('#img-after', img_src_after);
				 maskCanvas(false);
			 };
			 
			 
			 var reset_canvas_with_mask = function(){
				 reset_canvas();
				 maskCanvas(true);
			 }

			 var reset_all = function(){
				rects = [];
				$('#annotation').val("");
				reset_canvas_with_mask();
			 };
			 
			 custom_function = function(){
				rects = [];
				load_meta_data();
				reset_canvas_with_mask();
				makeCanvasClickable('#img-before');
				makeCanvasClickable('#img-after');
				$('.reset_canvas').click(function(){reset_all();});
			  // スライドバー(スライダー)を作る
			  $("#diff_slider").slider({value:1.0, min:0,max:1,step:0.05,change:brend,orientation:'vertical'});
				$('#btn-mask_image').click(reset_canvas_with_mask);
				$('#btn-raw_image').click(reset_canvas);
			 };
});
