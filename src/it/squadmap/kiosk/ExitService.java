package it.squadmap.kiosk;

import android.accessibilityservice.AccessibilityService;
import android.content.Intent;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;

/**
 * Listens to volume keys even while the target app is in front.
 * Typing SEQUENCE (U = volume up, D = volume down) within TIMEOUT_MS exits the kiosk.
 */
public class ExitService extends AccessibilityService {
    static final String SEQUENCE = "UUDDUD";
    static final long TIMEOUT_MS = 5000;

    private final StringBuilder typed = new StringBuilder();
    private long last;

    @Override
    protected boolean onKeyEvent(KeyEvent e) {
        int code = e.getKeyCode();
        if (e.getAction() != KeyEvent.ACTION_DOWN
                || (code != KeyEvent.KEYCODE_VOLUME_UP && code != KeyEvent.KEYCODE_VOLUME_DOWN)) {
            return false;
        }
        long now = System.currentTimeMillis();
        if (now - last > TIMEOUT_MS) typed.setLength(0);
        last = now;
        typed.append(code == KeyEvent.KEYCODE_VOLUME_UP ? 'U' : 'D');
        if (typed.length() > SEQUENCE.length()) typed.deleteCharAt(0);
        if (typed.toString().equals(SEQUENCE)) {
            typed.setLength(0);
            startActivity(new Intent(this, KioskActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    .putExtra("exit", true));
        }
        return false; // volume keeps working
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {}

    @Override
    public void onInterrupt() {}
}
