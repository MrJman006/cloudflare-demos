/**
* Returns an object that holds basic credentials as properties.
*
* @param {String} username - A username credential.
* @param {String} password - A password credential.
*
* @return {Object} - An object.
*/
function BasicCredentials(username, password)
{
    return {
        type: "basic",
        username: username,
        password: password
    };
}

/**
* Returns an object that holds bearer credentials as properties.
*
* @param {String} token - A bearer token credential.
*
* @return {Object} - An object.
*/
function BearerCredentials(token)
{
    return {
        type: "bearer",
        token: token
    };
}

/**
* Parse a set of authorization credentials from the supplied request.
*
* @param {Request} request - A request object.
*
* @return {BasicCredentials|BearerCredentials} - A credentials object.
*/
function parseAuthorizationCredentials(request)
{
    //
    // Get the authorization header.
    //

    let authHeader = request.headers.get('Authorization');

    if(!authHeader)
    {
        return null;
    }

    //
    // Validate the header format.
    //

    let authHeaderParams = authHeader.split(' ');

    if(authHeaderParams.length !== 2)
    {
        return null;
    }

    let [scheme, credentialsParam] = authHeaderParams;

    //
    // Process basic credentials.
    //

    if(scheme === "Basic")
    {
        //
        // Decode the credentials.
        //

        let buffer = Uint8Array.from(
            atob(credentialsParam),
            (character) => { return character.charCodeAt(0) }
        );

        let decoded = new TextDecoder().decode(buffer).normalize();

        let [username, password] = decoded.split(':');

        if(!username || !password)
        {
            return null;
        }

        let credentials = BasicCredentials(username, password);

        return credentials;
    }

    //
    // Process bearer credentials.
    //

    if(scheme === "Bearer")
    {
        let credentials = BearerCredentials(credentialsParam);

        return credentials;
    }

    //
    // Unsupported authorization credentials type.
    //

    return null;
}

export {
    BasicCredentials,
    BearerCredentials,
    parseAuthorizationCredentials
};
