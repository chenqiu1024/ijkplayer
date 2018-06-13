./init-ios.sh
./init-ios-openssl.sh
cd ios
./compile-ffmpeg.sh clean
./compile-openssl.sh clean
./compile-openssl.sh all 
./compile-ffmpeg.sh all 
