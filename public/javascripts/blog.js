
function update_basename() {
}

$(document).ready(function() {
	//console.log('ready');
	$("#basename").prop('disabled', true);
	$("#basename_lock").change(function() {
		$("#basename").prop('disabled', ! $("#basename_lock").is(':checked'));
	});
	$("#title").on('change, keyup paste', function() {
		// if basename is still locked and status is not published?
		//console.log( $(this).val() );
		var title = $(this).val().toLowerCase();
		title = title.replace(/^\s+|\s+$/g, "");
		title = title.replace(/[^\w-]+/g, '-');
		$("#basename").val(title);
	});

});
