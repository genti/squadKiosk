package it.squadmap.kiosk;

import android.app.Activity;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Bundle;
import android.os.Handler;
import android.view.Gravity;
import android.widget.TextView;

/**
 * Home activity of the totem. As Device Owner it pins itself + the target app in Lock Task
 * and keeps relaunching the target app whenever it comes back to the foreground.
 *
 * Exit (from adb only, nothing else can reach it on a locked device):
 *   adb shell am start -n it.squadmap.kiosk/.KioskActivity --ez exit true
 */
public class KioskActivity extends Activity {
    static final String TARGET = "it.davidegentilucci.squadmap";

    private DevicePolicyManager dpm;
    private ComponentName admin;
    private TextView status;
    private final Handler handler = new Handler();

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        dpm = getSystemService(DevicePolicyManager.class);
        admin = new ComponentName(this, AdminReceiver.class);
        status = new TextView(this);
        status.setGravity(Gravity.CENTER);
        status.setTextSize(20);
        setContentView(status);
        if (getIntent().getBooleanExtra("exit", false)) exitKiosk();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        if (intent.getBooleanExtra("exit", false)) exitKiosk();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (isFinishing()) return;
        if (!dpm.isDeviceOwnerApp(getPackageName())) {
            status.setText("Kiosk: non è Device Owner.\nadb shell dpm set-device-owner it.squadmap.kiosk/.AdminReceiver");
            return;
        }
        dpm.setLockTaskPackages(admin, new String[]{getPackageName(), TARGET});
        IntentFilter home = new IntentFilter(Intent.ACTION_MAIN);
        home.addCategory(Intent.CATEGORY_HOME);
        home.addCategory(Intent.CATEGORY_DEFAULT);
        dpm.addPersistentPreferredActivity(admin, home, new ComponentName(this, KioskActivity.class));
        dpm.setKeyguardDisabled(admin, true);
        dpm.setStatusBarDisabled(admin, true);
        startLockTask();
        launchTarget();
    }

    @Override
    protected void onPause() {
        super.onPause();
        handler.removeCallbacksAndMessages(null);
    }

    private void launchTarget() {
        Intent i = getPackageManager().getLaunchIntentForPackage(TARGET);
        if (i == null) {
            // Target not installed yet (or mid-update): retry until it shows up.
            status.setText("In attesa di " + TARGET + "…");
            handler.postDelayed(this::launchTarget, 3000);
            return;
        }
        status.setText("");
        startActivity(i);
    }

    private void exitKiosk() {
        handler.removeCallbacksAndMessages(null);
        if (dpm.isDeviceOwnerApp(getPackageName())) {
            dpm.setStatusBarDisabled(admin, false);
            dpm.setKeyguardDisabled(admin, false);
            dpm.clearPackagePersistentPreferredActivities(admin, getPackageName());
            dpm.setLockTaskPackages(admin, new String[0]);
        }
        try { stopLockTask(); } catch (Exception ignored) {}
        if (dpm.isDeviceOwnerApp(getPackageName())) dpm.clearDeviceOwnerApp(getPackageName());
        finish();
    }

    @Override
    public void onBackPressed() {
        // swallow: Back must not leave the totem
    }
}
