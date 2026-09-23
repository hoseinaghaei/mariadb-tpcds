--
-- MariaDB / MySQL dialect definitions for dsqgen.
--
-- MariaDB limits rows with a trailing  LIMIT n , the same form Netezza uses:
--   __LIMITA  text placed before  SELECT   (Oracle needs a wrapping subquery)
--   __LIMITB  text placed after   SELECT   (SQL Server needs TOP n here)
--   __LIMITC  text placed at end of query  (MariaDB: LIMIT n)
--
define __LIMITA = "";
define __LIMITB = "";
define __LIMITC = "limit %d";
define _END = "";
