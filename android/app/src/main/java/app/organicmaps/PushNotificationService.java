package app.organicmaps;

import android.util.Log;

import androidx.annotation.NonNull;

import com.google.android.gms.tasks.OnCompleteListener;
import com.google.android.gms.tasks.Task;
import com.google.firebase.messaging.*;

public class PushNotificationService extends FirebaseMessagingService {

    public PushNotificationService() {
        super();
        Log.d("Firebase","SERVICE INTIALIZED");
    }

    @Override
    public void onMessageReceived(RemoteMessage remoteMessage) {
        super.onMessageReceived(remoteMessage);
        Log.d("Firebase","ON MESSAGE RECEIVED CALLED" + remoteMessage.toString());

    }
    @Override
    public void onNewToken(@NonNull String token) {
        Log.d(this.getClass().getSimpleName(),"Refreshed token: " + token);
        // Pass the token to native code
        nativeSendTokenToCpp(token);
    }

    public static native void nativeSendTokenToCpp(String token);
}