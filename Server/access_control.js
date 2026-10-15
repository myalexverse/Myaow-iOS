'use strict';

// Resource authorization is separate from authentication. Never trust actor IDs in a request body.
function authorizeRoute(db, pathname, method, actor) {
    if (/^\/api\/v1\/(presence|profile)(\/|$)/.test(pathname) || /^\/api\/v1\/directory\/(lookup|search)$/.test(pathname)) {
        if (!actor) return 401;
        const target = pathname.match(/^\/api\/v1\/presence\/status\/([^/]+)$/);
        if (target && target[1] !== actor.myaow_id) return 403;
    }
    if (!/^\/api\/v1\/(groups|contacts|sessions|scheduled|scheduled-v2|tasks|moments|messages-v2|push|calls|webrtc)(\/|$)/.test(pathname)) return 200;
    if (!actor) return 401;
    const own = actor.myaow_id;
    const ownerPath = pathname.match(/^\/api\/v1\/(?:groups\/my|contacts\/blocked|moments\/feed)\/([^/]+)$/);
    if (ownerPath && ownerPath[1] !== own) return 403;
    const sessions = pathname.match(/^\/api\/v1\/sessions\/([^/]+)$/);
    if (sessions) {
        if (method === 'GET') return sessions[1] === own ? 200 : 403;
        const row = db.prepare('SELECT myaow_id FROM sessions WHERE session_id = ?').get(sessions[1]);
        return row?.myaow_id === own ? 200 : 403;
    }
    const group = pathname.match(/^\/api\/v1\/groups\/([^/]+)\/(join|leave|members|info|kick|promote|demote|tasks)$/);
    if (group) {
        const member = db.prepare('SELECT role FROM group_members WHERE group_id = ? AND myaow_id = ?').get(group[1], own);
        if (!member) return 403; // Joining needs a validated invitation; knowing a group ID is not an invitation.
        if (group[2] === 'tasks' && method === 'POST' && member.role !== 'admin' && db.prepare('SELECT task_policy FROM groups WHERE id=?').get(group[1])?.task_policy === 'admins') return 403;
        if (['info', 'kick', 'promote', 'demote'].includes(group[2]) && member.role !== 'admin') return 403;
    }
    const task = pathname.match(/^\/api\/v1\/tasks\/([^/]+)(?:\/complete)?$/);
    if (task) {
        const row = db.prepare('SELECT group_id, created_by_myaow_id, assignee_myaow_id FROM group_tasks WHERE id = ?').get(task[1]);
        if (!row) return 404;
        const member = db.prepare('SELECT role FROM group_members WHERE group_id = ? AND myaow_id = ?').get(row.group_id, own);
        const policy = db.prepare('SELECT task_policy FROM groups WHERE id=?').get(row.group_id)?.task_policy ?? 'assigned';
        if (member?.role !== 'admin' && (policy === 'admins' || (method === 'PUT' && policy === 'assigned' && row.created_by_myaow_id !== own && row.assignee_myaow_id !== own))) return 403;
        if (!member || (method === 'DELETE' && member.role !== 'admin' && row.created_by_myaow_id !== own)) return 403;
    }
    const scheduled = pathname.match(/^\/api\/v1\/scheduled\/([^/]+)$/);
    if (scheduled) {
        if (method === 'GET') return scheduled[1] === own ? 200 : 403;
        if (method === 'DELETE') {
            const row = db.prepare('SELECT sender_myaow_id FROM scheduled_messages WHERE id = ?').get(scheduled[1]);
            return row?.sender_myaow_id === own ? 200 : 403;
        }
        // Legacy scheduling stores plaintext; keep it closed until encrypted scheduled delivery exists.
        if (scheduled[1] === 'create' && method === 'POST') return 409;
    }
    const moment = pathname.match(/^\/api\/v1\/moments\/([^/]+)$/);
    if (moment && method === 'DELETE') {
        const row = db.prepare('SELECT author_id FROM moments WHERE id = ?').get(moment[1]);
        if (row?.author_id !== own) return 403;
    }
    return 200;
}

module.exports = { authorizeRoute };
