package app.organicmaps;

import android.content.Intent;
import android.os.Bundle;

import androidx.activity.EdgeToEdge;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.fragment.app.Fragment;

import app.organicmaps.base.BaseMwmFragmentActivity;
import app.organicmaps.help.HelpFragment;
import app.organicmaps.util.Constants;

public class AlertsActivity extends BaseMwmFragmentActivity {
    @Override
    protected Class<? extends Fragment> getFragmentClass()
    {
        return Alerts.class;
    }
}