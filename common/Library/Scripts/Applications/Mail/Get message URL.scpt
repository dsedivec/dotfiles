JsOsaDAS1.001.00bplist00�Vscript_�var app = Application.currentApplication();
app.includeStandardAdditions = true;
var Mail = Application("Mail");
var message = Mail.selection()[0];
var subject = message.subject();
var messageID = message.messageId();
app.setTheClipboardTo(`message:<${encodeURI(messageID)}>`)
app.displayNotification(`URL for message "${subject}" copied to clipboard`, {withTitle: "Get message URL"})                              �jscr  ��ޭ