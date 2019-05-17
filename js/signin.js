function onSignIn(google_user) {
  // The ID token needed to be passed to the backend is saved as a cookie
  var auth_response = google_user.getAuthResponse();
  var id_token = auth_response.id_token;
  var expire_ms = auth_response.expires_in*1000; //expires_in is the # of seconds from now until the id_token expires
  var d = new Date();
  d.setTime(d.getTime() + expire_ms);
  var expires = " expires="+d.toUTCString()+";";
  document.cookies = "id_token="+id_token+";"+expires+" path=/;";
  console.log(document.cookies);
  return id_token;
}

function getID_Token(first_run = true) {
  if (document.cookies == undefined) {
    //attempt login in future to define cookie
    return "";
  }

  var name = "id_token=";
  var value = "";
  var cookies_array = document.cookies.split(';');
  for(var i = 0; i < cookies_array.length; i++) {
    var c = cookies_array[i];
    while (c.charAt(0) == ' ') {
      c = c.substring(1);
    }
    if (c.indexOf(name) == 0) {
      value =  c.substring(name.length, c.length);
      break;
    }
  }

  //attempt login in future to define cookie
  //if (value === "" && first_run) {
    //var auth = gapi.auth2.getAuthInstance();
    //auth.signIn().then(onSignIn);
    //return getID_Token(false);
  //}

   return value;
}

 function signOut() {
  var auth = gapi.auth2.getAuthInstance(); //make sure instance exists before attemption to act on auth2
  gapi.auth2.signOut();
}
