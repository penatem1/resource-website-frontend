# Making Authenticated Requests

For requests that need user authentication, the web page needs the following:

### HTML preparation for login through Google

Our Google Sign-In client_id is required to authenticate requests, later it will be included in the JavaScript, for now it must be declared a meta tag in the HTML page. Google's ```platform.js``` script file prepares the page for making the requests with Google. Finally, ```signin.js``` contains our functions for sign-in use and request generation use.

In the ```<head>``` of HTML pages with authentication requirements:

    <meta name="google-signin-client_id" content="743489940041-kd5b4r3l4tiohluea0omifnhdf7db78t.apps.googleusercontent.com">
    <script src="https://apis.google.com/js/platform.js" async defer></script>
    <script type="text/javascript" src="/js/signin.js"></script>

The HTML (div element) for the sign-in button *currently* must exist *BEFORE* the async call to Google's ```platform.js```, more specifically, the button will not be created if the async call starts before the element is present in the page.

In the ```<body>``` of HTML page with authentication requirements, create a Google sign-in button with the following:

    <div class="g-signin2" data-onsuccess="onSignIn"></div>

In the JavaScript function that creates the request to the backend, the ```id_token``` cookie from the user login must be added to the request header. The result from ```getID_Token()``` contains this value, if there was no user login, the value returned is an empty string, resulting in status code response ```401: access denied``` from the backend.

DO NOT send the id_token over a request that is not SSL encrypted (http vs https).

In said function, include the following line during the creation of the XMLHTTP request:

    xmlhttp.setRequestHeader("id_token", getID_Token());

# Checking Authorization

Checking authorization may be required to dynamically display parts of a web page. Simply use this endpoint with the ```id_token``` in the header of the request:

    GET /api/v1/user_access/check/{permission_string}

This endpoint does not require authorization in order to receive a response.
