jQuery(function ($) {
			 
			 /* load from meta tags*/
			 var box;
			 var raw_image;
			 var mask_image;
			 var image_width;
			 
			 
			 var load_meta_data = function(){				
				box = JSON.parse($('#meta-box').attr('value'));
				raw_image = '/blob_images' + $('#meta-raw_image').attr('value');
				mask_image = '/blob_images' + $('#meta-mask_image').attr('value');
				image_width = parseFloat($('#meta-image_width').attr('value'));
				image_height = parseFloat($('#meta-image_height').attr('value'));
				box.x = Math.round(box.x*image_width);
				box.width = Math.round(box.width*image_width);
				box.y = Math.round(box.y*image_height);
				box.height = Math.round(box.height*image_height);
			 };
			 
			 // call back function of drawImage in print_image.
			 var draw_elems = function(){
			 console.log(box);
				$('#img').drawRect({
								 layer:true,
								 name: 'rect',
								 index: 1,
								 groups: ['rect-group'],
								 draggable: false,
								 strokeStyle: '#ff0000',
								 strokeWidth: 1,
								 x: box.x,
								 y: box.y,
								 width: box.width,
								 height: box.height,
								 fromCenter: false,
								 visible: true
								 });
			 };
			 
			 var print_raw_image = function(){			 
				$('#img').clearCanvas();
				$('#img').drawImage({
													 source:raw_image,
												   layer:true,
												   name:'image',
													 index:0,
													 x:0,y:0,
													 width:image_width,
													 height: image_height,
													 fromCenter: false,
													 load: draw_elems
												 });
				draw_elems();
			 };
			 var print_mask_image = function(){
				print_raw_image();
				$('#img').drawImage({
													 source:mask_image,
														layer:true,
														name:'image',
													 index:0,
													 x:0,y:0,
													 width: image_width,
													 height: image_height,
													 fromCenter: false,
														load: draw_elems,
														compositing:'darker'
														});
				draw_elems();
			 };
			 
			 custom_function = function(){
					load_meta_data();
					print_mask_image();
					$('#btn-mask_image').click(print_mask_image);
					$('#btn-raw_image').click(print_raw_image);
			 };
			 
			 $('#text_container').change(function(){
																	 console.log("hoge");
																	 $('#radio_container').prop('checked',true);
																	 });
												 
												 
/*
				var set_select2 = function(){
				var list = JSON.parse($('#meta-list_ingredient').attr('value'));
				$('#select-ingredient').select2({tags:list});

				list = JSON.parse($('#meta-list_seasoning').attr('value'));
				$('#select-seasoning').select2({tags:list});

				list = JSON.parse($('#meta-list_utensil').attr('value'));
				$('#select-utensil').select2({tags:list});

			 };
			 
			 
			 custom_function = function(){
				set_select2();
			 };
*/
});
