#import "CommentViewController.h"
#import "UIImageView+Gravatar.h"
#import "NSString+XMLExtensions.h"
#import "CommentsViewController.h"
#import "Comment.h"
#import "CommentService.h"
#import "EditCommentViewController.h"
#import "WPWebViewController.h"
#import "CommentView.h"
#import "InlineComposeView.h"
#import "ContextManager.h"
#import "WPFixedWidthScrollView.h"
#import "WPTableViewCell.h"
#import "DTLinkButton.h"
#import "WPToast.h"
#import "VerticallyStackedButton.h"
#import "SuggestionsTableViewController.h"
#import "SuggestionService.h"

typedef NS_ENUM(NSInteger, CommentViewButtonTag) {
    CommentViewButtonTagApprove,
    CommentViewButtonTagUnapprove
};

typedef NS_ENUM(NSInteger, CommentViewActionIndex) {
    CommentViewActionIndexDelete = 0
};

                
@interface CommentViewController () <UIActionSheetDelegate, InlineComposeViewDelegate, WPContentViewDelegate, EditCommentViewControllerDelegate, SuggestionsTableViewDelegate, InlineComposeViewMentionDelegate>

@property (nonatomic, strong) CommentView *commentView;
@property (nonatomic, strong) UIButton *trashButton;
@property (nonatomic, strong) UIButton *approveButton;
@property (nonatomic, strong) UIButton *spamButton;
@property (nonatomic, strong) UIBarButtonItem *editButton;
@property (nonatomic, strong) UIButton *replyButton;
@property (nonatomic, strong) InlineComposeView *inlineComposeView;
@property (nonatomic, strong) Comment *reply;
@property (nonatomic, strong) EditCommentViewController *editCommentViewController;
@property (nonatomic, assign) BOOL transientReply;
@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;

@end

@implementation CommentViewController

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    _reply = nil;
    _inlineComposeView.delegate = nil;
    _inlineComposeView = nil;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.commentView = [[CommentView alloc] initWithFrame:self.view.frame];
    self.commentView.contentProvider = self.comment;
    self.commentView.delegate = self;

    WPFixedWidthScrollView *scrollView = [[WPFixedWidthScrollView alloc] initWithRootView:self.commentView];
    scrollView.alwaysBounceVertical = YES;
    if (IS_IPAD) {
        scrollView.contentInset = UIEdgeInsetsMake(WPTableViewTopMargin, 0, WPTableViewTopMargin, 0);
        scrollView.contentWidth = WPTableViewFixedWidth;
    } else {
        scrollView.contentInset = UIEdgeInsetsMake(0, 0, WPTableViewTopMargin, 0);
    }
    scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.view = scrollView;
    self.view.backgroundColor = [UIColor whiteColor];

    self.replyButton = [VerticallyStackedButton buttonWithType:UIButtonTypeSystem];
    [self.replyButton setImage:[UIImage imageNamed:@"icon-comments-reply"] forState:UIControlStateNormal];
    [self.replyButton setTitle:NSLocalizedString(@"Reply", @"Verb, reply to a comment") forState:UIControlStateNormal];
    [self.replyButton setAccessibilityLabel: NSLocalizedString(@"Reply", @"Spoken accessibility label.")];
    [self.replyButton addTarget:self action:@selector(replyAction:) forControlEvents:UIControlEventTouchUpInside];
    [self.commentView addCustomActionButton:self.replyButton];
    
    self.approveButton = [VerticallyStackedButton buttonWithType:UIButtonTypeSystem];
    [self.approveButton setImage:[UIImage imageNamed:@"icon-comments-approve"] forState:UIControlStateNormal];
    [self.approveButton setAccessibilityLabel:NSLocalizedString(@"Toggle approve or unapprove", @"Spoken accessibility label.")];
    [self.approveButton addTarget:self action:@selector(approveOrUnapproveAction:) forControlEvents:UIControlEventTouchUpInside];
    [self.commentView addCustomActionButton:self.approveButton];

    self.spamButton = [VerticallyStackedButton buttonWithType:UIButtonTypeSystem];
    [self.spamButton setImage:[UIImage imageNamed:@"icon-comments-spam"] forState:UIControlStateNormal];
    [self.spamButton setTitle:NSLocalizedString(@"Spam", @"Verb, mark a comment as spam") forState:UIControlStateNormal];
    [self.spamButton setAccessibilityLabel:NSLocalizedString(@"Mark as spam", @"Spoken accessibility label.")];
    [self.spamButton addTarget:self action:@selector(spamAction:) forControlEvents:UIControlEventTouchUpInside];
    [self.commentView addCustomActionButton:self.spamButton];
    
    self.trashButton = [VerticallyStackedButton buttonWithType:UIButtonTypeSystem];
    [self.trashButton setImage:[UIImage imageNamed:@"icon-comments-trash"] forState:UIControlStateNormal];
    [self.trashButton setTitle:NSLocalizedString(@"Trash", @"Verb, move a comment to the trash") forState:UIControlStateNormal];
    [self.trashButton setAccessibilityLabel:NSLocalizedString(@"Move to trash", @"Spoken accessibility label.")];
    [self.trashButton addTarget:self action:@selector(deleteAction:) forControlEvents:UIControlEventTouchUpInside];
    [self.commentView addCustomActionButton:self.trashButton];

    self.editButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit target:self action:@selector(editAction:)];
    [self.editButton setAccessibilityLabel:NSLocalizedString(@"Edit comment", @"Spoken accessibility label.")];
    self.navigationItem.rightBarButtonItem = self.editButton;

    [self.view addSubview:self.commentView];

    self.inlineComposeView = [[InlineComposeView alloc] initWithFrame:CGRectZero];
    self.inlineComposeView.delegate = self;
    self.inlineComposeView.shouldDeleteTagWithBackspace = YES;
    self.inlineComposeView.mentionDelegate = self;
    [self.view addSubview:self.inlineComposeView];

    if (self.comment) {
        [self showComment:self.comment];
   }

    // For tapping to dismiss the keyboard
    self.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];

    // Don't show current title in the next-view back button
    UIBarButtonItem *backButton = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil];
    self.navigationItem.backBarButtonItem = backButton;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleKeyboardDidShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleKeyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];

    // Get rid of any transient reply if popping the view
    // (ideally transient replies should be handled more cleanly)
    if ([self isMovingFromParentViewController] && self.transientReply) {
        CommentService *commentService = [[CommentService alloc] initWithManagedObjectContext:[[ContextManager sharedInstance] mainContext]];
        [commentService deleteComment:self.reply success:nil failure:nil];
    }
}


#pragma mark - Instance methods

- (void)updateApproveButton
{
    if ([self.comment.status isEqualToString:@"approve"]) {
        [self.approveButton setTag:CommentViewButtonTagUnapprove];
        [self.approveButton setImage:[UIImage imageNamed:@"icon-comments-unapprove"] forState:UIControlStateNormal];
        [self.approveButton setTitle:NSLocalizedString(@"Unapprove", @"Verb, unapprove a comment") forState:UIControlStateNormal];
        [self.approveButton setAccessibilityLabel:NSLocalizedString(@"Approve", @"Spoken accessibility label.")];
        return;
    }
    
    [self.approveButton setTag:CommentViewButtonTagApprove];
    [self.approveButton setImage:[UIImage imageNamed:@"icon-comments-approve"] forState:UIControlStateNormal];
    [self.approveButton setTitle:NSLocalizedString(@"Approve", @"Verb, approve a comment") forState:UIControlStateNormal];
    [self.approveButton setAccessibilityLabel:NSLocalizedString(@"Unapprove", @"Spoken accessibility label.")];
}

- (void)showComment:(Comment *)comment
{
    self.comment = comment;
    [self.commentView reloadData];
    [self updateApproveButton];
}

- (NSAttributedString *)postTitleString
{
    NSString *postTitle;

    if (self.comment.postTitle != nil) {
        postTitle = [[self.comment.postTitle stringByDecodingXMLCharacters] trim];
    } else {
        postTitle = NSLocalizedString(@"(No Title)", nil);
    }
    NSString *postTitleOn = NSLocalizedString(@"on ", @"(Comment) on (Post Title)");
    NSString *combinedString = [postTitleOn stringByAppendingString:postTitle];
    NSRange titleRange = [combinedString rangeOfString:postTitle];
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:combinedString];
    [attributedString addAttribute:NSForegroundColorAttributeName value:[WPStyleGuide newKidOnTheBlockBlue] range:titleRange];

    return attributedString;
}

#pragma mark - Comment moderation

- (void)deleteComment
{
    CommentService *commentService = [[CommentService alloc] initWithManagedObjectContext:[[ContextManager sharedInstance] mainContext]];
    [commentService deleteComment:self.comment success:nil failure:nil];

    // Note: the parent class of CommentsViewController will pop this as a result of NSFetchedResultsChangeDelete
}

- (void)showEditCommentViewWithAnimation:(BOOL)animate
{
    NSString *nibName = NSStringFromClass([EditCommentViewController class]);
    self.editCommentViewController = [[EditCommentViewController alloc] initWithNibName:nibName
                                                                                 bundle:nil];
    self.editCommentViewController.delegate = self;
    self.editCommentViewController.comment  = self.comment;

    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:self.editCommentViewController];
    navController.modalPresentationStyle = UIModalPresentationFormSheet;
    navController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    navController.navigationBar.translucent = NO;
    [self presentViewController:navController animated:animate completion:nil];
}

- (void)updateStateOfActionButtons:(BOOL)state
{
    [self updateStateOfActionButton:self.spamButton toState:state];
    [self updateStateOfActionButton:self.trashButton toState:state];
    [self updateStateOfActionButton:self.approveButton toState:state];
    [self updateStateOfActionButton:self.replyButton toState:state];
}

- (void)updateStateOfActionButton:(UIButton*)button toState:(BOOL)state
{
    button.enabled = state;
}


#pragma mark - EditCommentViewController Delegate

- (void)editCommentViewController:(EditCommentViewController *)sender finishedWithUpdates:(BOOL)hasUpdates
{
    if (hasUpdates) {
        [self showComment:sender.comment];
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}


#pragma mark - Actions

- (void)approveOrUnapproveAction:(id)sender
{
    UIButton *button = sender;
    CommentService *commentService = [[CommentService alloc] initWithManagedObjectContext:[[ContextManager sharedInstance] mainContext]];
    [self updateStateOfActionButtons:NO];
    
    // Show an activity indicator in place of the button until the operation completes
    UIActivityIndicatorView *indicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [indicatorView setBackgroundColor:[UIColor whiteColor]];
    indicatorView.frame = CGRectMake(-5.0f, 1.0f, button.frame.size.width + 10.0f, button.frame.size.height - 1.0f);
    [button addSubview:indicatorView];
    [indicatorView startAnimating];
    if (button.tag == CommentViewButtonTagApprove) {
        [commentService approveComment:self.comment
                               success:^{
                                   [self updateStateOfActionButtons:YES];
                                   [indicatorView removeFromSuperview];
                               }
                               failure:^(NSError *error) {
                                   self.comment.status = @"unapprove";
                                   [self updateStateOfActionButtons:YES];
                                   [indicatorView removeFromSuperview];
                                   [WPError showAlertWithTitle:NSLocalizedString(@"Error", @"")
                                                       message:NSLocalizedString(@"The comment could not be moderated.", @"Error message when comment could not be moderated")];
                               }];
    } else {
        [commentService unapproveComment:self.comment
                                 success:^{
                                     [self updateStateOfActionButtons:YES];
                                     [indicatorView removeFromSuperview];
                                 }
                                 failure:^(NSError *error){
                                     self.comment.status = @"approve";
                                     [self updateStateOfActionButtons:YES];
                                     [indicatorView removeFromSuperview];
                                     [WPError showAlertWithTitle:NSLocalizedString(@"Error", @"")
                                                         message:NSLocalizedString(@"The comment could not be moderated.", @"Error message when comment could not be moderated")];
                                 }];
    }
    
    [self updateApproveButton];
}

- (void)postTitleAction:(id)sender
{
    [self openInAppWebView:[NSURL URLWithString:self.comment.link]];
}

- (void)deleteAction:(id)sender
{
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"Are you sure you want to delete this comment?", @"")
                                                             delegate:self
                                                    cancelButtonTitle:NSLocalizedString(@"Cancel", @"")
                                               destructiveButtonTitle:NSLocalizedString(@"Delete", @"")
                                                    otherButtonTitles:nil];
    actionSheet.actionSheetStyle = UIActionSheetStyleAutomatic;
    [actionSheet showFromToolbar:self.navigationController.toolbar];
}

- (void)spamAction:(id)sender
{
    CommentService *commentService = [[CommentService alloc] initWithManagedObjectContext:[[ContextManager sharedInstance] mainContext]];
    [commentService spamComment:self.comment success:nil failure:nil];
}

- (void)editAction:(id)sender
{
    [self showEditCommentViewWithAnimation:YES];
}

- (void)replyAction:(id)sender
{
    if (self.commentsViewController.blog.isSyncingComments) {
        [self showSyncInProgressAlert];
    } else {
        if (self.inlineComposeView.isDisplayed) {
            [self.inlineComposeView dismissComposer];
        } else {
            CommentService *commentService = [[CommentService alloc] initWithManagedObjectContext:[[ContextManager sharedInstance] mainContext]];
            self.reply = [commentService restoreReplyForComment:self.comment];
            self.transientReply = YES;
            self.inlineComposeView.text = self.reply.content;
            [self.inlineComposeView displayComposer];
        }
    }
}

#pragma mark - Gesture Actions

- (void)handleTap:(UITapGestureRecognizer *)gesture
{
    if (self.inlineComposeView.isDisplayed) {
        [self.inlineComposeView dismissComposer];
    }
}

#pragma mark - Notification Handlers

- (void)handleKeyboardDidShow:(NSNotification *)notification
{
    CGRect keyboardRect = [[notification.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    UIScrollView *scrollView = (UIScrollView *)self.view;
    scrollView.contentInset = UIEdgeInsetsMake(0.f, 0.f, CGRectGetHeight(keyboardRect), 0.f);
    [self.view addGestureRecognizer:self.tapGesture];
}

- (void)handleKeyboardWillHide:(NSNotification *)notification
{
    UIScrollView *scrollView = (UIScrollView *)self.view;
    scrollView.contentInset = UIEdgeInsetsMake(0.f, 0.f, 0.f, 0.f);
    [self.view removeGestureRecognizer:self.tapGesture];
}

#pragma mark - UIActionSheet delegate methods

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == CommentViewActionIndexDelete) {
        [self deleteComment];
    }
}


#pragma mark UIWebView delegate methods

- (BOOL)webView:(UIWebView *)inWeb
    shouldStartLoadWithRequest:(NSURLRequest *)inRequest
    navigationType:(UIWebViewNavigationType)inType
{
    if (inType == UIWebViewNavigationTypeLinkClicked) {
        [self openInAppWebView:[inRequest URL]];
        return NO;
    }
    return YES;
}

- (void)openInAppWebView:(NSURL*)url
{
    Blog *blog = [[self comment] blog];

    if ([[url description] length] > 0) {
        WPWebViewController *webViewController = [[WPWebViewController alloc] init];
        webViewController.url = url;

        if (blog.isPrivate && [blog isWPcom]) {
            webViewController.username = blog.username;
            webViewController.password = blog.password;
        }

        [self.navigationController pushViewController:webViewController animated:YES];
    }
}

- (void)showSyncInProgressAlert
{
    [WPError showAlertWithTitle:NSLocalizedString(@"Info", @"Info alert title") message:NSLocalizedString(@"The blog is syncing with the server. Please try later.", @"") withSupportButton:NO];
    //the blog is using the network connection and cannot be stoped, show a message to the user
}

#pragma mark - InlineComposeViewDelegate methods

- (void)composeView:(InlineComposeView *)view didSendText:(NSString *)text
{
    self.reply.content = text;

    // try to save it
    [[ContextManager sharedInstance] saveContext:self.reply.managedObjectContext];

    self.inlineComposeView.enabled = NO;
    self.transientReply = NO;

    CommentService *commentService = [[CommentService alloc] initWithManagedObjectContext:self.reply.managedObjectContext];
    [commentService uploadComment:self.reply success:^{
        self.reply.status = CommentStatusApproved;

        [self.inlineComposeView clearText];
        self.inlineComposeView.enabled = YES;
        [self.inlineComposeView dismissComposer];

        [WPToast showToastWithMessage:NSLocalizedString(@"Replied", @"User replied to a comment")
                             andImage:[UIImage imageNamed:@"action_icon_replied"]];

    } failure:^(NSError *error) {
        // reset to draft status, AppDelegate automatically shows UIAlert when comment fails
        self.reply.status = CommentStatusDraft;

        self.inlineComposeView.enabled = YES;
        [self.inlineComposeView displayComposer];

        DDLogError(@"Could not reply to comment: %@", error);
    }];
}

// when the reply changes, save it to the comment
- (void)textViewDidChange:(UITextView *)textView
{
    self.reply.content = self.inlineComposeView.text;
    [[ContextManager sharedInstance] saveContext:self.reply.managedObjectContext];
}

#pragma mark - WPContentViewDelegate

- (void)contentView:(WPContentView *)contentView didReceiveAuthorLinkAction:(id)sender
{
    NSURL *url = [NSURL URLWithString:self.comment.author_url];
    [self openInAppWebView:url];
}

- (void)contentView:(WPContentView *)contentView didReceiveLinkAction:(id)sender
{
    [self openInAppWebView:((DTLinkButton *)sender).URL];
}

#pragma mark - InlineComposeViewMentionDelegate

- (void)composeViewDidStartAtMention:(InlineComposeView *)view
{
    NSNumber *siteID = self.comment.blog.blogID;
    if ([[SuggestionService shared] shouldShowSuggestionsPageForSiteID:siteID]) {
        SuggestionsTableViewController *suggestionsController = [[SuggestionsTableViewController alloc] initWithSiteID:siteID];
        suggestionsController.delegate = self;
        [self.navigationController pushViewController:suggestionsController animated:YES];
    }
}

#pragma mark - SuggestionsTableViewDelegate

- (void)suggestionTableView:(SuggestionsTableViewController *)suggestionsTableViewController
            didSelectString:(NSString *)string
{
    self.inlineComposeView.text = [self.inlineComposeView.text stringByAppendingString:string];
}

- (void)suggestionViewDidDisappear:(SuggestionsTableViewController *)suggestionsController
{
    suggestionsController.delegate = nil;
    [self.inlineComposeView becomeFirstResponder];
}

@end
