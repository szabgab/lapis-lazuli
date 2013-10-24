


http://en.wikipedia.org/wiki/Lapis_lazuli


Specification
=============


Registration:
   Username: *
   Display Name:*
   Email Address: *
   Initial Password: *
   Password Confirm: *
   Website URL:

   CAPTCHA
   About: (text box)

=> Show page a "Profile Created" and send e-mail with confirmation link
   Including as parameters: the URL of the blog a blog_id=1, user_id=2407, token=long random string

  Clicking ont the confirmation link I get to the "Sign in" page
  tha also says "Thanks for the confirmation. Please sign in"


Sign in:
  Username:
  Password:
  Rememeber me? (checkbox)
 "Sign In" button

  Link to "Sign Up"
  Link to "Forgot your Password?


 Or Sign in using:
   Open ID (which is going away)
   Live Journal
   WordPress.com
   Google

Edit Profile:
  Username cannot be changed
  Display Name:
  Email address:
  New Password:
  Confirm Password:
  Userpic (Browse to upload)
  About (text box)
  Save (button)


Create Entry:
  Title:
  Body (text) with HTML editor
  Extended (text) with HTML editor
  Tags: A comma separated list of values
  Format: (how the body and extended texts are displayed to the reader)
    None
    Convert Line Breaks
    Markdown
    Markdown with SmaryPants
    Rich Text
    Textile 2
  Publihsing
    Status:
      Published
      Draft
      Scheduled
    Publish Date: (date and time selectors)
    Basename:
      (text field that automatically gets filled from the title
       including only \w characters and replacing space by _ (or by -)
      The filed is read-only but there is a button that allows to unlock
      the field. this will be the display URL of the article.
    Categories:
      Is this displaed anywher?
    Feedback:
      Accept Comments []
      Accept TrackBacks []
      Outbound TrackBack URLs ???
    Assets: (TBD)
Two butons: Save and Preview
  The content is autosaved.


Manage Entries:
  lists all the entries written by the user (paged)
 [] Published? Title  Category Author Created View
 Clicking on an entry leads to the "Create Entry" page
 but now it is called "Edit Entry"


Preferences:
  General:
     Name:
     Description: (text)
     Timezone
     License: ?
  Publishing:
     File extension: html  (but could be changed)
     Preferred Archive:
     TBD
  Entry: TBD
  Comments:
    Enable/Disable (for all the posts of this user)
    TBD



Commenting:
  Just type some text (some HTML might be allowed)
  Or if ther is already a comment click "Reply"


Search: full textsearch on the posts and comments





Layout of the reader pages:
Main page:  On the main page a list of articles:
  <% title %>
  By <% author%> on <% date %>
  <% abstract %>

  <a href=""><% number_of_comments %> comments</a> 
  <a href="">Continue reading</a>
    (or Permalink if the extended part was empty)

  At the bottom of the page one can click on
  Page 2  that leads to /page/2
  and then /page/3 etc

  /page/1 is also available but IMHO should redirect to the
    main page
  Goes all the way to /page/563 showing thevery first entry.


The Permalink of each post is
   /users/USER_NAME/YYYY/MM/BASENAME.html
   It showsboth the body and the extented part of the post
   together with the tags and the comments.

   #comments is the anchor to the top of the comments
   Each comment has an achon #comment-COMMENTID
   (the commentid is a number)


Feeds:

