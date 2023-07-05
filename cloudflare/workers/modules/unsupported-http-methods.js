import {HTTP_STATUS_CODES} from "./http-status-codes.js";

/**
* Generates an unsupported HTTP method response object.
*
* @param {Headers} headers - A headers object.
*
* @return {Response} - A response object.
*/
function generateUnsupportedHttpMethodResponse(apiName, headers)
{
    let response = new Response(
        `HTTP method not implemented for the ${apiName} API.`,
        {
            status: HTTP_STATUS_CODES.NOT_IMPLEMENTED,
            headers
        }
    );

    return response;
}

export {
    generateUnsupportedHttpMethodResponse
};
