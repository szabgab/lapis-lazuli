
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
			return false;
		}

		// if status is published, do not change the basename
		if ( $("#status").val() == 'published' ) {
			return false;
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

	$("#cancel").click(function() {
		var form = 	$(this).parent();
		if ( form.attr('id') == 'post_form' ) {
			alert("Cancel Not implemented");
		} else if ( form.attr('id') == 'comment_editor_form' ) {
			$("#comment_editor_section").hide();
			$("#comment_editor").val('');
			$("#comment_alert").html('');
			$("#comment_preview").html('');
		} else {
			alert("Strange, apparently this cancel button is not implemented yet");
		}
		return false;
	});

	$("#submit").click(function() {
		var form = 	$(this).parent();
		//console.log(form.attr('id'));
		//return;
		var data = form.serialize();
		if ( form.attr('id') == 'post_form' ) {
			// TODO validate before submitting!
			// It seems serialize does not fetch the value of disabled fields
			data += "&basename=" + $("#basename").val();
			//console.log(data);
			$.post("/u/create-post", data, function() {
				console.log('success');
				alert('success');
			}).fail(function() {
				console.log('fail');
				alert('fail');
			});
			return false;
		} else if ( form.attr('id') == 'comment_editor_form' ) {
			$("#comment_editor_section").hide();
			$("#comment_alert").html('');
			$("#comment_preview").html('Thank you for commenting!');
			console.log(form.attr('action'));
			return true;
		} else {
			alert("Strange, apparently this submit button is not implemented yet");
			return false;
		}
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

	$("#openid_login_form").hide();
	$("#show_openid_login_form").click(function () {
		$("#regular_login_form").hide();
		$("#openid_login_form").show();
		return false;
	});
	$("#show_regular_login_form").click(function () {
		$("#openid_login_form").hide();
		$("#regular_login_form").show();
		return false;
	});

	$("a.edit").click(function (){
		//console.log($(this).attr('id'));
		var id = $(this).attr('id');
		if (id == 'new_comment') {
			//console.log('new');
			$("#comment_editor_section").show();
		} else {
			var comment_id = id.substr(5);
			var data = {
				'post_id' : $("#page_id").val(),
				'comment_id': comment_id,
			};
			console.log(data);
			$.get("/u/get-comment", data, function(resp) {
				//console.log('success');
				//console.log(resp);
				$("#comment_id").val(comment_id);
				$("#comment_editor_section").show();
				$("#comment_editor").val(resp);
			}).fail(function() {
				console.log('fail');
				alert('fail');
			});
			// open editor with the text of this comment and
			// set the comment_id in the form to be the comment_id
		}
		return false; 
	});


});
