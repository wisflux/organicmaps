package app.organicmaps;

import static android.Manifest.permission.ACCESS_COARSE_LOCATION;
import static android.Manifest.permission.ACCESS_FINE_LOCATION;
import static android.Manifest.permission.POST_NOTIFICATIONS;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.Keep;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.StringRes;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;

import app.organicmaps.display.DisplayManager;
import app.organicmaps.location.LocationHelper;
import app.organicmaps.util.Config;
import app.organicmaps.util.LocationUtils;
import app.organicmaps.util.ThemeUtils;
import app.organicmaps.util.concurrency.UiThread;
import app.organicmaps.util.log.Logger;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;

import java.io.IOException;
import java.util.Objects;

public class SplashActivity extends AppCompatActivity
{
  private static final String TAG = SplashActivity.class.getSimpleName();

  private static final long DELAY = 100;

  private boolean mCanceled = false;

  @SuppressWarnings("NotNullFieldNotInitialized")
  @NonNull
  private ActivityResultLauncher<String[]> mPermissionRequest;

  // Declare the launcher at the top of your Activity/Fragment:
  private final ActivityResultLauncher<String> requestPermissionLauncher =
          registerForActivityResult(new ActivityResultContracts.RequestPermission(), isGranted -> {
            if (isGranted) {
              // FCM SDK (and your app) can post notifications.
            } else {
              // TODO: Inform user that that your app will not show notifications.
            }
          });

  private void askNotificationPermission() {
    // This is only necessary for API level >= 33 (TIRAMISU)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      if (ContextCompat.checkSelfPermission(this, POST_NOTIFICATIONS) ==
              PackageManager.PERMISSION_GRANTED) {
        Log.d(TAG, "PERMISSION_GRANTED");
        // FCM SDK (and your app) can post notifications.
      } else if (shouldShowRequestPermissionRationale(POST_NOTIFICATIONS)) {
        // TODO: display an educational UI explaining to the user the features that will be enabled
        //       by them granting the POST_NOTIFICATION permission. This UI should provide the user
        //       "OK" and "No thanks" buttons. If the user selects "OK," directly request the permission.
        //       If the user selects "No thanks," allow the user to continue without notifications.
      } else {
        // Directly ask for the permission
        requestPermissionLauncher.launch(POST_NOTIFICATIONS);
      }
    }
  }

  @NonNull
  private final Runnable mInitCoreDelayedTask = this::init;

  @Override
  protected void onCreate(@Nullable Bundle savedInstanceState)
  {
    super.onCreate(savedInstanceState);

    final Context context = getApplicationContext();
    final String theme = Config.getCurrentUiTheme(context);
    if (ThemeUtils.isDefaultTheme(context, theme))
      setTheme(R.style.MwmTheme_Splash);
    else if (ThemeUtils.isNightTheme(context, theme))
      setTheme(R.style.MwmTheme_Night_Splash);
    else
      throw new IllegalArgumentException("Attempt to apply unsupported theme: " + theme);

    UiThread.cancelDelayedTasks(mInitCoreDelayedTask);
    setContentView(R.layout.activity_splash);
    mPermissionRequest = registerForActivityResult(new ActivityResultContracts.RequestMultiplePermissions(),
        result -> Config.setLocationRequested());
    this.askNotificationPermission();

    if (DisplayManager.from(this).isCarDisplayUsed())
    {
      startActivity(new Intent(this, MapPlaceholderActivity.class));
      finish();
    }
  }

  @Override
  protected void onResume()
  {
    super.onResume();
    if (mCanceled)
      return;
    if (!Config.isLocationRequested() && !LocationUtils.checkCoarseLocationPermission(this))
    {
      Logger.d(TAG, "Requesting location permissions");
      mPermissionRequest.launch(new String[]{
          ACCESS_COARSE_LOCATION,
          ACCESS_FINE_LOCATION
      });
      return;
    }

    UiThread.runLater(mInitCoreDelayedTask, DELAY);
  }

  @Override
  protected void onPause()
  {
    super.onPause();
    UiThread.cancelDelayedTasks(mInitCoreDelayedTask);
  }

  @Override
  protected void onDestroy()
  {
    super.onDestroy();
    mPermissionRequest.unregister();
    mPermissionRequest = null;
  }

  private void showFatalErrorDialog(@StringRes int titleId, @StringRes int messageId)
  {
    mCanceled = true;
    new MaterialAlertDialogBuilder(this, R.style.MwmTheme_AlertDialog)
        .setTitle(titleId)
        .setMessage(messageId)
        .setNegativeButton(R.string.ok, (dialog, which) -> SplashActivity.this.finish())
        .setCancelable(false)
        .show();
  }

  private void init()
  {
    MwmApplication app = MwmApplication.from(this);
    boolean asyncContinue = false;
    try
    {
      asyncContinue = app.init(this::processNavigation);
    } catch (IOException e)
    {
      showFatalErrorDialog(R.string.dialog_error_storage_title, R.string.dialog_error_storage_message);
      return;
    }

    if (Config.isFirstLaunch(this) && LocationUtils.checkLocationPermission(this))
    {
      final LocationHelper locationHelper = app.getLocationHelper();
      locationHelper.onEnteredIntoFirstRun();
      if (!locationHelper.isActive())
        locationHelper.start();
    }

    if (!asyncContinue)
      processNavigation();
  }

  // Called from MwmApplication::nativeInitFramework like callback.
  @Keep
  @SuppressWarnings({"unused", "unchecked"})
  public void processNavigation()
  {
    if (isDestroyed())
    {
      Logger.w(TAG, "Ignore late callback from core because activity is already destroyed");
      return;
    }

    // Re-use original intent to retain all flags and payload.
    // https://github.com/organicmaps/organicmaps/issues/6944
    final Intent intent = Objects.requireNonNull(getIntent());
    intent.setComponent(new ComponentName(this, DownloadResourcesLegacyActivity.class));
    // Flags like FLAG_ACTIVITY_NEW_TASK and FLAG_ACTIVITY_RESET_TASK_IF_NEEDED will break the cold start of the app.
    // https://github.com/organicmaps/organicmaps/pull/7287
    intent.setFlags(intent.getFlags() & (Intent.FLAG_ACTIVITY_FORWARD_RESULT | Intent.FLAG_GRANT_READ_URI_PERMISSION));

    Config.setFirstStartDialogSeen(this);
    startActivity(intent);
    finish();
  }
}
