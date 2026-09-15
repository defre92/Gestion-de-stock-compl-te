-- Annulation de 202602270016.
--
-- Ne redescend PAS le compte promu vers ADMIN : rien n'a memorise lequel
-- c'etait avant (comme pour 202602270015, la valeur precedente n'est pas
-- restauree faute d'avoir ete sauvegardee). Si ce role est retire ici alors
-- qu'un compte l'utilise encore, ce compte se retrouve avec un role_id
-- orphelin - c'est pourquoi la ligne SUPER_ADMIN n'est supprimee que si plus
-- aucun compte ne l'utilise.
--
-- Pour revenir completement a l'ancien comportement, il faut aussi restaurer
-- le code : demo-data.php et migrate.php verifiaient role_code = 'ADMIN', et
-- la restriction cote frontend (applyNavAccess) se basait sur canWrite('users').

DELETE FROM roles
WHERE code = 'SUPER_ADMIN'
  AND NOT EXISTS (
      SELECT 1 FROM users u
      INNER JOIN roles r ON r.id = u.role_id
      WHERE r.code = 'SUPER_ADMIN'
  );
