package com.paidviewpoint.ar;

import android.os.Handler;

import androidx.annotation.NonNull;

import com.google.ar.core.ArCoreApk;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/** ArPlugin */
public class ArPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  public static MethodChannel channel;


  public static ActivityPluginBinding activityPluginBinding;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "ar");
    channel.setMethodCallHandler(this);

    flutterPluginBinding.getPlatformViewRegistry().registerViewFactory("com.paidviewpoint.ar", new ArcoreViewFactory(flutterPluginBinding.getBinaryMessenger()));
  }

  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
    activityPluginBinding = binding;
  }

  @Override
  public void onDetachedFromActivity() {
    activityPluginBinding = null;
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    activityPluginBinding = null;
  }

  @Override
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
    activityPluginBinding = binding;
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    if (call.method.equals("isAvailable")) {
      checkAr(result);
    } else {
      result.notImplemented();
    }
  }
  
  void checkAr(@NonNull Result result) {
    try {
      ArCoreApk.Availability availability = ArCoreApk.getInstance().checkAvailability(activityPluginBinding.getActivity());
      if (availability.isTransient()) {
        // Continue to query availability at 5Hz while compatibility is checked in the background.
        new Handler().postDelayed(new Runnable() {
          @Override
          public void run() {
            checkAr(result);
          }
        }, 200);
      }
      else if (availability.isSupported()) {
        result.success(true);
      } else { // The device is unsupported or unknown.
        result.success(false);
      }
    } catch (Exception e){

    }
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
  }
}
