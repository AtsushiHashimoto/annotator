jQuery(function ($) {
			 // global variables
			 var DEBUG = 1;
       var min_work_time = 0;
			 var do_break = false;

			 // timerが切れたときに終了するボタンを押せるようにする．
			 var on_timer_expiration = function(){
					$('.timer-hide').show(0);
			 };
			 
			 
			 
			 var set_timer = function(){
			 
				if($('#meta-min_work_time').length){
				 min_work_time = Number($('#meta-min_work_time').attr('value'));
			   $('.timer').countdown({until: min_work_time, compact: true, layout: '{mnn}{sep}{snn}', description: '', onExpiry: on_timer_expiration});
				}
				else{
					on_timer_expiration();
				}
	
			 };
			 
			 var set_logout = function(){
					$('a.logout').click(function(){
													 $('form#logout-form').submit();			
													 });
			 };
			 
			 
			 var set_unbreakable = function(){
					if($('#breakable').length>0){
						return;
					}
					$('.breakable_link').click(function(){
																 do_break = true;
															});
					
					$(window).bind("beforeunload", function() {
												 if(!do_break){
													return "作業を終了する場合，右上の「作業を終了する」ボタンを利用してください．\nブラウザの戻るボタンなどは使わないで下さい．";
												 }
												 });
//					console.log('set unbreakable');
			 }
			 
			 var set_skip = function(){
				$('.skip').click(function(){
												 var result = confirm("このタスクを飛ばしてもよろしいですか?");
												 if(result){
													window.location.href = '/task'
												 }
												 });
			 };
			 

			 $(document).ready(function() {
												 set_timer();
												 set_logout();
												 set_unbreakable();
												 set_skip();
												 custom_function();
												 });
			 
});
