#import "EditPageViewController.h"
#import "AbstractPost.h"
#import "ContextManager.h"
#import "PostService.h"
#import "Page.h"
#import "Blog.h"
#import "PageSettingsViewController.h"

@implementation EditPageViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.titlePlaceholderText = NSLocalizedString(@"Page title", @"Placeholder text for the title field on Pages screen.");
}

- (NSString *)editorTitle
{
    NSString *title = @"";
    if (self.ownsPost) {
        title = NSLocalizedString(@"New Page", @"New Page Editor screen title.");
    } else {
        if ([self.post.postTitle length] > 0) {
            title = self.post.postTitle;
        } else {
            title = NSLocalizedString(@"Edit Page", @"Page Editor screen title.");
        }
    }
    self.navigationItem.backBarButtonItem.title = title;
    return title;
}

- (void)didSaveNewPost
{
    // Noop.
    // The superclass triggers a tab switch with this method which we don't want for pages.
}

- (Class)classForSettingsViewController
{
    return [PageSettingsViewController class];
}

- (void)geotagNewPost
{
    // Noop. Pages do not support geolocation.
}

- (AbstractPost *)createNewDraftForBlog:(Blog *)blog {
    return [PostService createDraftPageInMainContextForBlog:blog];
}

@end
