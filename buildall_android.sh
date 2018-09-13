./init-android-openssl.sh
./init-android.sh
cd android/contrib/
./compile-openssl.sh clean
./compile-ffmpeg.sh clean
./compile-openssl.sh all
./compile-ffmpeg.sh all

