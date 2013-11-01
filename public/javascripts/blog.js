
function update_basename() {
}

function editor_preview() {
	var abstract_html = $("#abstract_editor").val();
	var body_html     = $("#body_editor").val();

	var html = abstract_html + ' ' + body_html;
	var hits = html.match(/<\w+/g);
	// console.log(hits);
	var editor_alert = '';
	if (hits) {
		for (i=0; i<hits.length; i++) {
			//console.log(hits[i]);
			tag = hits[i].substr(1);
			//console.log(tag);
			if (! accepted_html_tags[tag]) {
				editor_alert = "The tag <b>" + tag + "</b> is not accepted";
				html = '';
				break;
			}
		}
	}
	$("#editor_alert").html(editor_alert);

	$("#editor_preview").html(html);
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
			return False;
		}

		// if status is published, do not change the basename
		if ( $("#status").val() == 'published' ) {
			return False;
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

	$("#comment_editor").bind('input propertychange', function() {
		var html = $("#comment_editor").val();
		var hits = html.match(/<\w+/g);
		// console.log(hits);
		var comment_alert = '';
		if (hits) {
			for (i=0; i<hits.length; i++) {
				//console.log(hits[i]);
				tag = hits[i].substr(1);
				//console.log(tag);
				if (! accepted_html_tags[tag]) {
					comment_alert = "The tag <b>" + tag + "</b> is not accepted";
					html = '';
					break;
				}
			}
		}
		$("#comment_alert").html(comment_alert);
		
		$("#comment_preview").html(html);
	});

	$("#abstract_editor").bind('input propertychange', function() {
		editor_preview();
	});

	$("#body_editor").bind('input propertychange', function() {
		editor_preview();
	});

});
