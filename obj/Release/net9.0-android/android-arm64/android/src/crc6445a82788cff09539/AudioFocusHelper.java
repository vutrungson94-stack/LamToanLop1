package crc6445a82788cff09539;


public class AudioFocusHelper
	extends java.lang.Object
	implements
		mono.android.IGCUserPeer,
		android.media.AudioManager.OnAudioFocusChangeListener
{
/** @hide */
	public static final String __md_methods;
	static {
		__md_methods = 
			"n_onAudioFocusChange:(I)V:GetOnAudioFocusChange_IHandler:Android.Media.AudioManager/IOnAudioFocusChangeListenerInvoker, Mono.Android, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null\n" +
			"";
		mono.android.Runtime.register ("LamToanLop1.Platforms.Android.AudioFocusHelper, LamToanLop1", AudioFocusHelper.class, __md_methods);
	}

	public AudioFocusHelper ()
	{
		super ();
		if (getClass () == AudioFocusHelper.class) {
			mono.android.TypeManager.Activate ("LamToanLop1.Platforms.Android.AudioFocusHelper, LamToanLop1", "", this, new java.lang.Object[] {  });
		}
	}

	public void onAudioFocusChange (int p0)
	{
		n_onAudioFocusChange (p0);
	}

	private native void n_onAudioFocusChange (int p0);

	private java.util.ArrayList refList;
	public void monodroidAddReference (java.lang.Object obj)
	{
		if (refList == null)
			refList = new java.util.ArrayList ();
		refList.add (obj);
	}

	public void monodroidClearReferences ()
	{
		if (refList != null)
			refList.clear ();
	}
}
