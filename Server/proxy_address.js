'use strict';
const {isIP}=require('node:net');
function clientAddress(req, trusted=false) {
    const supplied=req.headers['x-myaow-client-ip'];
    // Enable only when the relay port is private and the proxy overwrites this header.
    return trusted && typeof supplied==='string' && isIP(supplied) ? supplied : req.socket.remoteAddress || 'unknown';
}
module.exports={clientAddress};
