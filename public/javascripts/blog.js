
function update_basename() {
}

$(document).ready(function() {
	//console.log('ready');
	$("#basename").prop('disabled', true);
	$("#basename_lock").change(function() {
		var is_checked = $("#basename_lock").is(':checked');
		$("#basename").prop( 'disabled', ! is_checked );
	});
	$("#title").on('change, keyup paste', function() {
		// if basename is not locked
		if ( $("#basename_lock").is(':checked') ) {
			return;
		}

		// if status is published, do not change the basename
		if ( $("#status").val() == 'published' ) {
			return;
		}
		// TODO we should probably make sure the basename cannot be changed
		// at all after the article was published.
		// And we might want to allow for moving the article (and then probably
		// we'll want to set up redirection from the old path to the new path.

		//console.log( $(this).val() );
		var title = $(this).val().toLowerCase();
		title = title.replace(/^\s+|\s+$/g, "");
		title = title.replace(/[^\w-]+/g, '-');
		$("#basename").val(title);
	});
	$("#submit").click(function() {
		var data = $("#post_form").serialize();
		//console.log('hi');

		// It seems serialize does not fetch the value of disabled fields
		//console.log(data.title);
		data += "&basename=" + $("#basename").val();
		//console.log(data);
		$.post("/u/create-post", data, function() {
			console.log('success');
			alert('success');
		}).fail(function() {
			console.log('fail');
			alert('fail');
		});
	});
});
