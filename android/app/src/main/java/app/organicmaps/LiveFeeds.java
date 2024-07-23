package app.organicmaps;

import android.content.Intent;
import android.os.Bundle;

import androidx.fragment.app.Fragment;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;

import app.organicmaps.base.BaseMwmFragment;
import app.organicmaps.util.Constants;

/**
 * A simple {@link Fragment} subclass.
 * create an instance of this fragment.
 */
public class LiveFeeds extends BaseMwmFragment {

    @Override
    public View onCreateView(LayoutInflater inflater, ViewGroup container,
                             Bundle savedInstanceState) {
        // Inflate the layout for this fragment
        View root = inflater.inflate(R.layout.fragment_live_feeds, container, false);
        new WebContainerDelegate(root, Constants.Url.DRIMS_LIVE)
        {
            @Override
            protected void doStartActivity(Intent intent)
            {
                startActivity(intent);
            }
        };

        return root;
    }
}