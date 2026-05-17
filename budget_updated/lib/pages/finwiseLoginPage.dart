import 'package:budget/colors.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/finwise_mvp.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/accountAndBackup.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class FinWiseLoginPage extends StatefulWidget {
  const FinWiseLoginPage({required this.onLoggedIn, super.key});

  final VoidCallback onLoggedIn;

  @override
  State<FinWiseLoginPage> createState() => _FinWiseLoginPageState();
}

class _FinWiseLoginPageState extends State<FinWiseLoginPage> {
  final TextEditingController emailController =
      TextEditingController(text: "demo@finwise.local");
  final TextEditingController passwordController = TextEditingController();
  bool obscurePassword = true;
  bool isLoadingGoogle = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> completeLogin({bool demo = false}) async {
    final String email = demo || emailController.text.trim().isEmpty
        ? "demo@finwise.local"
        : emailController.text.trim();

    await sharedPreferences.setBool(finWiseMockLoggedInKey, true);
    await sharedPreferences.setString(finWiseMockEmailKey, email);

    // Only set hasOnboarded to true for demo mode - real users need to go through onboarding
    if (demo) {
      if (appStateSettings["hasOnboarded"] != true) {
        await updateSettings("hasOnboarded", true, updateGlobalState: false);
      }
      if ((appStateSettings["username"] ?? "").toString().trim().isEmpty) {
        await updateSettings("username", "FinWise User",
            pagesNeedingRefresh: [], updateGlobalState: false);
      }
    }

    widget.onLoggedIn();
  }

  Future<void> signInWithGoogle() async {
    setState(() {
      isLoadingGoogle = true;
    });

    try {
      // Use default GoogleSignIn - credentials come from google-services.json
      // The serverClientId helps link to the OAuth consent screen
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: "360848321721-tt54le4junsun55gu7o0gauo3ljgfn08.apps.googleusercontent.com",
      );

      // Trigger the Google Sign-In flow
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        // User cancelled the sign-in
        setState(() {
          isLoadingGoogle = false;
        });
        return;
      }

      // Get the Google Sign-In authentication tokens
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create Firebase credentials
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase
      final UserCredential firebaseUser =
          await FirebaseAuth.instance.signInWithCredential(credential);

      // Get user email
      final String? userEmail = firebaseUser.user?.email;

      if (userEmail != null) {
        // Save Firebase login state
        await sharedPreferences.setBool(finWiseMockLoggedInKey, true);
        await sharedPreferences.setString(finWiseMockEmailKey, userEmail);
        await sharedPreferences.setBool("firebaseAuthEnabled", true);

        // Set user email in settings
        await updateSettings("currentUserEmail", userEmail,
            pagesNeedingRefresh: [], updateGlobalState: true);

        // Set username from Google account if not already set
        if ((appStateSettings["username"] ?? "").toString().trim().isEmpty) {
          String displayName = googleUser.displayName ?? "FinWise User";
          await updateSettings("username", displayName,
              pagesNeedingRefresh: [], updateGlobalState: true);
        }

        // For new users (hasOnboarded is false), DO NOT set it to true here
        // The OnBoardingPage will be shown automatically because hasOnboarded is false
        // After they complete onboarding, hasOnboarded will be set to true there
      }

      widget.onLoggedIn();
    } catch (e) {
      print("Google Sign-In Error: $e");
      String errorMessage = "Failed to sign in with Google";

      // Provide more specific error messages
      if (e.toString().contains("_SIGN_IN_FAILED")) {
        errorMessage = "Google Sign-In failed. Please check Firebase Console: Authentication → Google Sign-In is enabled";
      } else if (e.toString().contains("network_error")) {
        errorMessage = "Network error. Please check your internet connection";
      } else if (e.toString().contains("platform")) {
        errorMessage = "Platform error. Check SHA-1 fingerprint in Firebase";
      } else {
        errorMessage = "Error: ${e.toString()}";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    } finally {
      setState(() {
        isLoadingGoogle = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 24,
              vertical: 32,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 64,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  TextFont(
                    text: finWiseAppName,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 8),
                  TextFont(
                    text: "Personal finance made simple",
                    fontSize: 16,
                    textAlign: TextAlign.center,
                    textColor: getColor(context, "textLight"),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 36),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: "Email",
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => completeLogin(),
                    decoration: InputDecoration(
                      labelText: "Password",
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip:
                            obscurePassword ? "Show password" : "Hide password",
                        onPressed: () {
                          setState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Button(
                    label: "Login",
                    onTap: () => completeLogin(),
                  ),
                  const SizedBox(height: 14),
                  // Google Sign-In Button
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: colorScheme.outline),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: isLoadingGoogle ? null : signInWithGoogle,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (isLoadingGoogle)
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.primary,
                                  ),
                                )
                              else
                                Icon(
                                  Icons.g_mobiledata_rounded,
                                  size: 28,
                                  color: colorScheme.onSurface,
                                ),
                              const SizedBox(width: 12),
                              TextFont(
                                text: "Continue with Google",
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: () => completeLogin(demo: true),
                    child: const Text("Continue as demo user"),
                  ),
                  const SizedBox(height: 18),
                  TextFont(
                    text:
                        "Sign in with Google to sync your data across devices",
                    fontSize: 13,
                    textAlign: TextAlign.center,
                    textColor: getColor(context, "textLight"),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
