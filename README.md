

http://en.wikipedia.org/wiki/Lapis_lazuli


TODO
=====

- Add published time stamp to the front page
- Add number of comments (0)
- In test Generate at least one post without "body"
- Add Paging to main page (allow the admin to set the page size)
- Limit the accepted HTML tags and test this
  <b>, <a href=""></a>, <ul>, <ol> <li>
- Allow comments on the article specific page
- Add search capability

- On the page of the post add By line






- When deleting a user ask for confirmation
  and remove all the posts and comments the user made.
- Allow disabling users (by administrators)
- ?? make sure the display names are unique as well (we probably don't want to let the readers be confused)


Show the personal picture of each user next to their post and next to their
comment (probably a smaller picture).


Allow login with some other services:
   Open ID (which is going away)
   Live Journal
   WordPress.com
   Google
   ???



Create Entry:
  Title:
  Body (text) with HTML editor
  Extended (text) with HTML editor
  Tags: A comma separated list of values
  Format: (how the body and extended texts are displayed to the reader)
    None
    Convert Line Breaks
    Markdown
    Markdown with SmartyPants
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

