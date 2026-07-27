SET NAMES utf8mb4;

-- Cette colonne existe deja sur les installations ou elle a ete ajoutee a la
-- main (hors migration versionnee) - le IF NOT EXISTS evite une erreur sur
-- ces installations tout en corrigeant les installations neuves ou elle
-- manquait completement.
ALTER TABLE delivery_lines
    ADD COLUMN IF NOT EXISTS serial_id BIGINT NULL AFTER product_id;

ALTER TABLE delivery_lines
    ADD CONSTRAINT fk_delivery_lines_serial
    FOREIGN KEY IF NOT EXISTS (serial_id) REFERENCES product_serials (id) ON DELETE SET NULL;
