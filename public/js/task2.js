jQuery(function ($) {
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
});
