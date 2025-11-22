// get all the files from `secure-files/media/pictures
fetch('./secure-files/media/pictures').then(res => console.log("res is ", res)).catch(err => console.log("err is ", err));