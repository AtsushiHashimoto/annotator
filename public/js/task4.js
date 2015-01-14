jQuery(function ($) {
			 
			 /* load from meta tags*/
			 var load_meta_data = function(){				
			 };
			 

			 custom_function = function(){
					$('html, body').animate({scrollTop: $(".task4_prev_segment").offset().top-100}, 0);
				
					$('html, body').animate({scrollTop: $(".task4_current_segment").offset().top-100}, 2000);
					$('#task4select').select2();
					load_meta_data();
			 };
			 
												 
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
