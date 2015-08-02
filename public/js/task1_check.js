jQuery(function ($) {
			 var point1 = {};
			 var point2 = {};
			 var diff_image_path = new Image();
			 var mask_image_path = new Image();
			 var img_src_before = new Image();
			 var img_src_after = new Image();
			 var image_width;
			 var image_height;

			 
			 
			 var load_meta_data = function(){
				img_src_before.src = '/data_path/task1/' + $('#meta-before_image').attr('value');
				img_src_after.src = '/data_path/task1/' + $('#meta-after_image').attr('value');
				diff_image_path.src = '/data_path/task1/' + $('#meta-diff_image').attr('value');
				mask_image_path.src = '/data_path/task1/' + $('#meta-mask_image').attr('value');
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
					console.log(id);
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
			 var DrawFixedRect = function(node,rect){
				console.log(node);
				DrawRect(node,rect,3,'#ffffff',2);
				DrawRect(node,rect,4,'#a0ff00',1);
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
				$(id).drawImage({
													source:mask_image_path,
													layer:true,
													name:'mask',
													index:2,
													x:0,y:0,
													width:image_width,
													height:image_height,
													fromCenter: false,
													compositing:'darker',
													visible: false});
			 
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
				
			 }
			 
			 			 
			 var reset_canvas = function(){			 
				 $('canvas').removeLayers();
				 initCanvas('.img-before', img_src_before);
				 initCanvas('.img-after', img_src_after);
				 maskCanvas(false);
				 var rects;
				 $('.micro_task').each(function(index,elem){
															ann_elem = $(elem).find('.annotation')[0];
															json_str = $(ann_elem).val();
															console.log(json_str);
															if(json_str==""){
															 return;
															}
															rects = $.parseJSON(json_str);
															rects.forEach(function(rect){
																						console.log(rect);
																						var tar;
																						
																						if('put'==rect['type']){
																						tar = $(elem).find('.img-after')[0];
																						}
																						else{
																						tar = $(elem).find('.img-before')[0];
																						}
																						console.log($(tar));
																						$(tar).drawRect({
																														layer:true,
																													 draggable: false,
																														strokeStyle: "#ff0000",
																													 strokeWidth: 2,
																													 x: rect.x, y: rect.y,
																													 width: rect.width, height: rect.height,
																													 fromCenter: false,
																														index:3
																													 });
																						
																						
																						});
															console.log(rects);
															
															});

			 };
			 
			 
			 var reset_canvas_with_mask = function(){
				 reset_canvas();
				 maskCanvas(true);
			 }

			 
			 custom_function = function(){
				load_meta_data();
				reset_canvas_with_mask();
				$('.reset_canvas').click(function(){reset_all();});
			 
			 
			  // スライドバー(スライダー)を作る
			  $(".diff_slider").slider({value:1.0, min:0,max:1,step:0.05,change:brend,orientation:'vertical'});
				$('.btn-mask_image').click(reset_canvas_with_mask);
				$('.btn-raw_image').click(reset_canvas);
			 };
});
