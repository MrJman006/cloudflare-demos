import {HTTP_STATUS_CODES} from "./http-status-codes.js";

/**
* A list of origins that are whitelisted for the API.
*
* @type {Array}
*/
let _ALLOWED_ORIGINS = [
    "http://127.0.0.1:9999",
    "https://mrjman006.github.io"
];

/**
* Checks if the request has an allowed origin. Returns true if the origin is
* allowed and false otherwise.
*
* @param {Request} request - A request object.
*
* @return {Boolean} - A boolean.
*/
function hasAllowedOrigin(request)
{
    let origin = request.headers.get("origin");

    if(!_ALLOWED_ORIGINS.includes(origin))
    {
        return false;
    }

    return true;
}

/**
* Generates a forbidden origin response object.
*
* @param {Headers} headers - A headers object.
*
* @return {Response} - A response object.
*/
function generateForbiddenOriginResponse(headers)
{
    let response = new Response(
        "Forbidden origin.",
        {
            status: HTTP_STATUS_CODES.FORBIDDEN,
            headers: headers
        }
    );

    return response;
}

export {
    hasAllowedOrigin,
    generateForbiddenOriginResponse
};
