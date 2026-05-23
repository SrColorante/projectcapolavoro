-- Migration v2: Group chats, file attachments in messages, chat customization support
-- Run this if you already have the chatProject database from chat.sql

USE chatProject;

-- 1. Alter 'chat' table to support groups
ALTER TABLE chat
    ADD COLUMN is_group TINYINT(1) NOT NULL DEFAULT 0,
    ADD COLUMN name VARCHAR(100) BINARY NULL,
    ADD COLUMN created_by BIGINT UNSIGNED NULL,
    ADD COLUMN avatar_url VARCHAR(500) BINARY NULL,
    ADD CONSTRAINT FK_CHAT_CREATOR FOREIGN KEY (created_by) REFERENCES utenti(IDutente);

-- Make utente1 and utente2 nullable for group chats (they will be NULL when is_group=1)
ALTER TABLE chat
    MODIFY COLUMN utente1 BIGINT UNSIGNED NULL,
    MODIFY COLUMN utente2 BIGINT UNSIGNED NULL;

-- 2. Create 'chat_members' table for group participants
CREATE TABLE chat_members (
    chat_id BIGINT UNSIGNED NOT NULL,
    user_id BIGINT UNSIGNED NOT NULL,
    joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    role ENUM('admin','member') NOT NULL DEFAULT 'member',
    PRIMARY KEY (chat_id, user_id),
    CONSTRAINT FK_CM_CHAT FOREIGN KEY (chat_id) REFERENCES chat(IDchat) ON DELETE CASCADE,
    CONSTRAINT FK_CM_USER FOREIGN KEY (user_id) REFERENCES utenti(IDutente) ON DELETE CASCADE
);

-- 3. Alter 'messaggi' to support group chat and file attachments
ALTER TABLE messaggi
    ADD COLUMN chat_id BIGINT UNSIGNED NULL,
    ADD COLUMN file_attachment_id BIGINT UNSIGNED NULL,
    MODIFY COLUMN reciverID BIGINT UNSIGNED NULL,
    ADD CONSTRAINT FK_MSG_CHAT FOREIGN KEY (chat_id) REFERENCES chat(IDchat) ON DELETE CASCADE,
    ADD CONSTRAINT FK_MSG_FILE FOREIGN KEY (file_attachment_id) REFERENCES shared_files(id) ON DELETE SET NULL;

-- 4. Alter 'shared_files' to optionally link to a message
ALTER TABLE shared_files
    ADD COLUMN message_id INT UNSIGNED NULL,
    ADD CONSTRAINT FK_SF_MESSAGE FOREIGN KEY (message_id) REFERENCES messaggi(id) ON DELETE SET NULL;

-- Add index on message_id for fast lookups
CREATE INDEX idx_shared_files_message ON shared_files(message_id);
CREATE INDEX idx_messaggi_chat ON messaggi(chat_id);
