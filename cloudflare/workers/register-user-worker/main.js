import {HTTP_STATUS_CODES} from "../modules/http-status-codes.js";
import {hasAllowedOrigin, generateForbiddenOriginResponse} from "../modules/http-origin-access-control.js";
import {generateUnsupportedHttpMethodResponse} from "../modules/unsupported-http-methods.js";
import {parseAuthorizationCredentials, BasicCredentials} from "../modules/http-authorization-headers.js";
import {bcrypt} from "../modules/bcrypt.js";

/**
* The name of this API endpoint.
*
* @type {String}
*/
let API_NAME = "register-user";

/**
* The access control headers for this API endpoint.
*
* @type {Headers}
*/
let ACCESS_CONTROL_HEADERS = new Headers({
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'PUT, HEAD, OPTIONS',
    'Access-Control-Allow-Headers': '*'
});

/**
* A list of emails that are allowed to be registered using this API endpoint.
* If the list is 'null' any email can be registered.
*
* @type {Array}
*/
let ALLOWED_EMAILS = null

/**
* Handle requests using the PUT method.
*
* The PUT method is used to create and register a new user. The PUT method
* requires a basic authorization header that is the new user's authorization
* credentials. The PUT method will return a message response detailing the
* result of user registration.
*
* @param {Request} request - A request object.
* @param {Object} request.headers - An object containing the headers.
* @param {String} request.headers.authorization - A string containing authorization parameters.
*
* @return {Promise<Response>} - A response object wrapped in a Promise. The
*   response object will contain text content describing the result of user
*   registration.
*/
async function handlePUT(request)
{
    //
    // Parse basic credentials.
    //

    let credentials = parseAuthorizationCredentials(request);

    if(!credentials || credentials.type !== "basic")
    {
        let response = new Response(
            "Missing authorization credentials or incorrect format.",
            {
                status: HTTP_STATUS_CODES.BAD_REQUEST,
                headers: ACCESS_CONTROL_HEADERS
            }
        );

        return response;
    }

    let {username: email, password} = credentials;

    //
    // Make sure the requested email is in the allowed user list.
    //

    if(ALLOWED_EMAILS && !ALLOWED_EMAILS.includes(email))
    {
        let response = new Response(
            "The supplied email is not eligible to be registered.",
            {
                status: HTTP_STATUS_CODES.BAD_REQUEST,
                headers: ACCESS_CONTROL_HEADERS
            }
        );

        return response;
    }

    //
    // Don't register emails that are already registered.
    //

    let password_hash = await USERS.get(email);

    if(password_hash)
    {
        let response = new Response(
            "The supplied email is already registered.",
            {
                status: HTTP_STATUS_CODES.BAD_REQUEST,
                headers: ACCESS_CONTROL_HEADERS
            }
        );

        return response;
    }

    //
    // Register the email.
    //

    password_hash = bcrypt.hashSync(password);

    await USERS.put(email, password_hash);

    password_hash = await USERS.get(email);

    if(!password_hash)
    {
        let response = new Response(
            "Failed to register the supplied email.",
            {
                status: HTTP_STATUS_CODES.INTERNAL_SERVER_ERROR,
                headers: ACCESS_CONTROL_HEADERS
            }
        );

        return response;
    }

    let response = new Response(
        "Successfully registered the supplied email.",
        {
            status: HTTP_STATUS_CODES.OK,
            headers: ACCESS_CONTROL_HEADERS
        }
    );

    return response;
}

/**
* Handles incoming requests for this API endpoint and returns an appropriate
* response.
*
* @param {Request} request - A request object.
*
* @return {Promise<Response>} - A response object wrapped in a Promise.
*/
async function handleRequest(request)
{
    //
    // Block origins that are not on the whitelist.
    //

    let originAllowed = hasAllowedOrigin(request);

    if(!originAllowed)
    {
        let response = generateForbiddenOriginResponse(ACCESS_CONTROL_HEADERS);
        return response;
    }

    //
    // Respond to HEAD and OPTIONS methods with a simple 'Ok' message response.
    //

    if(request.method == "HEAD" || request.method == "OPTIONS")
    {
        let response = new Response(
            "Ok",
            {
                status: HTTP_STATUS_CODES.OK,
                headers: ACCESS_CONTROL_HEADERS
            }
        );

        return response;
    }

    //
    // Respond to supported methods.
    //

    if(request.method == "PUT")
    {
        let response = await handlePUT(request);
        return response;
    }

    //
    // Respond to unsupported methods.
    //

    let response = generateUnsupportedHttpMethodResponse(
        API_NAME,
        ACCESS_CONTROL_HEADERS
    );

    return response;
}

//
// Listen for incoming requests to this API endpoint and respond.
//

addEventListener(
    'fetch',
    function(event)
    {
        let request = event.request;
        let promise = handleRequest(request);
        event.respondWith(promise);
    }
);
