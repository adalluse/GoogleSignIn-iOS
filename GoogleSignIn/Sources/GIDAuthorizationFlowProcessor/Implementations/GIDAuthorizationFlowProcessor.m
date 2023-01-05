#import "GoogleSignIn/Sources/GIDAuthorizationFlowProcessor/Implementations/GIDAuthorizationFlowProcessor.h"

#import "GoogleSignIn/Sources/Public/GoogleSignIn/GIDConfiguration.h"

#import "GoogleSignIn/Sources/GIDEMMSupport.h"
#import "GoogleSignIn/Sources/GIDSignInCallbackSchemes.h"
#import "GoogleSignIn/Sources/GIDSignInInternalOptions.h"
#import "GoogleSignIn/Sources/GIDSignInPreferences.h"

#ifdef SWIFT_PACKAGE
@import AppAuth;
#else
#import <AppAuth/AppAuth.h>
#endif

NS_ASSUME_NONNULL_BEGIN

// Parameters for the auth and token exchange endpoints.
static NSString *const kAudienceParameter = @"audience";

static NSString *const kIncludeGrantedScopesParameter = @"include_granted_scopes";
static NSString *const kLoginHintParameter = @"login_hint";
static NSString *const kHostedDomainParameter = @"hd";

@implementation GIDAuthorizationFlowProcessor {
  // AppAuth external user-agent session state.
  id<OIDExternalUserAgentSession> _currentAuthorizationFlow;
  // AppAuth configuration object.
  OIDServiceConfiguration *_appAuthConfiguration;
}

@synthesize start;

# pragma mark - Public API

- (BOOL)isStarted {
  return _currentAuthorizationFlow != nil;
}

- (void)startWithOptions:(GIDSignInInternalOptions *)options
              emmSupport:(NSString *)emmSupport
              completion:(void (^)(OIDAuthorizationResponse *_Nullable authorizationResponse,
                                   NSError *_Nullable error))completion {
  GIDSignInCallbackSchemes *schemes =
      [[GIDSignInCallbackSchemes alloc] initWithClientIdentifier:options.configuration.clientID];
  NSURL *redirectURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@:%@",
                                             [schemes clientIdentifierScheme],
                                             kBrowserCallbackPath]];

  NSMutableDictionary<NSString *, NSString *> *additionalParameters = [@{} mutableCopy];
  additionalParameters[kIncludeGrantedScopesParameter] = @"true";
  if (options.configuration.serverClientID) {
    additionalParameters[kAudienceParameter] = options.configuration.serverClientID;
  }
  if (options.loginHint) {
    additionalParameters[kLoginHintParameter] = options.loginHint;
  }
  if (options.configuration.hostedDomain) {
    additionalParameters[kHostedDomainParameter] = options.configuration.hostedDomain;
  }

#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST
  [additionalParameters addEntriesFromDictionary:
      [GIDEMMSupport parametersWithParameters:options.extraParams
                                   emmSupport:emmSupport
                       isPasscodeInfoRequired:NO]];
#elif TARGET_OS_OSX || TARGET_OS_MACCATALYST
  [additionalParameters addEntriesFromDictionary:options.extraParams];
#endif // TARGET_OS_OSX || TARGET_OS_MACCATALYST
  additionalParameters[kSDKVersionLoggingParameter] = GIDVersion();
  additionalParameters[kEnvironmentLoggingParameter] = GIDEnvironment();
  
  NSURL *authorizationEndpointURL = [GIDSignInPreferences authorizationEndpointURL];
  NSURL *tokenEndpointURL = [GIDSignInPreferences tokenEndpointURL];
  OIDServiceConfiguration *appAuthConfiguration =
      [[OIDServiceConfiguration alloc] initWithAuthorizationEndpoint:authorizationEndpointURL
                                                       tokenEndpoint:tokenEndpointURL];

  OIDAuthorizationRequest *request =
      [[OIDAuthorizationRequest alloc] initWithConfiguration:appAuthConfiguration
                                                    clientId:options.configuration.clientID
                                                      scopes:options.scopes
                                                 redirectURL:redirectURL
                                                responseType:OIDResponseTypeCode
                                        additionalParameters:additionalParameters];
  _currentAuthorizationFlow = [OIDAuthorizationService
      presentAuthorizationRequest:request
#if TARGET_OS_IOS || TARGET_OS_MACCATALYST
         presentingViewController:options.presentingViewController
#elif TARGET_OS_OSX
                 presentingWindow:options.presentingWindow
#endif // TARGET_OS_OSX
                        callback:^(OIDAuthorizationResponse *_Nullable authorizationResponse,
                                   NSError *_Nullable error) {
    completion(authorizationResponse, error);
  }];
}

- (BOOL)resumeExternalUserAgentFlowWithURL:(NSURL *)url {
  if ([_currentAuthorizationFlow resumeExternalUserAgentFlowWithURL:url]) {
    _currentAuthorizationFlow = nil;
    return YES;
  } else {
    return NO;
  }
}

- (void)cancelAuthenticationFlow {
  [_currentAuthorizationFlow cancel];
  _currentAuthorizationFlow = nil;
}

@end

NS_ASSUME_NONNULL_END