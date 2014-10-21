jQuery(function ($) {
			 // global variables
			 var DEBUG = 1;
       var min_time = 0;			 			 

			 // timerが切れたときに終了するボタンを押せるようにする．
			 var on_timer_expiration = function(){
				$('#go_to_next').show(0);
			 };
			 
			 var set_timer = function(){
			 
				if($('.min_time').length){
				 min_time = Number($('.min_time').attr('val'));
			   $('.timer').countdown({until: min_time, compact: true, layout: '{mnn}{sep}{snn}', description: '', onExpiry: on_timer_expiration});
				}
	
			 };
			 
			 var set_logout = function(){
					$('a.logout').click(function(){
													 $('form#logout-form').submit();			
													 });
			 };
			 
			 $(document).ready(function() {
												 set_timer();
												 set_logout();
												 });
});
