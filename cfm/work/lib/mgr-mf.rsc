# ============================================================
# cfm lib/mgr-mf.rsc – Manifest-Regeln: welche Dateien ein Gerät bekommt (D70)
# Gehört zur Version: $cfmManifests lädt diese Datei aus der Version, die ein Gerät bekommt
# (archive/vN, beim Probelauf plan/). Eine neue Datei, die eine Rolle braucht, wirkt damit genau
# ab der Version, die sie mitbringt – auch solange der installierte Manager-Code älter ist (TODO 47).
# Regeln abwärtskompatibel halten: Dateien, die ältere Versionen nicht haben, sind optional.
#   $cfmMfWant name=<Host> role=<Rollen, kommagetrennt> fx=<Dateiindex der Version>
#   -> Liste {Pfad; Import 1/0; Pflicht 1/0} in Importreihenfolge
# ============================================================

:global cfmMfWant do={
  :local rl ("," . [:tostr $role] . ",")
  :local want ({})
  :set ($want->[:len $want]) ({"lib/lib.rsc";1;1})
  # WLAN-Teil der Bibliothek (D68) nur für Geräte, die WLAN rendern (der CAPsMAN aus cm hat eine dieser
  # Rollen); optional: Versionen vor D68 haben ihn noch in lib.rsc
  :if ($rl ~ ",(ap|capsman|manager),") do={ :set ($want->[:len $want]) ({"lib/lib-wifi.rsc";1;0}) }
  :set ($want->[:len $want]) ({"lib/agent.rsc";0;1})
  # Manager-Funktionen: alle Module lib/mgr-*.rsc der Version (installiert die Rolle manager)
  :if ($rl ~ ",manager") do={
    :foreach p,h in=$fx do={ :if ($p ~ "^lib/mgr-") do={ :set ($want->[:len $want]) ({$p;0;1}) } }
  }
  :foreach f in={"global.rsc";"vlans.rsc";"profiles.rsc";"wifi.rsc";"wireguard.rsc"} do={ :set ($want->[:len $want]) ({$f;1;1}) }
  # optional (D62): ältere Versionen haben keine leases.rsc - Ringe auf einer solchen bleiben gültig
  :set ($want->[:len $want]) ({"leases.rsc";1;0})
  # authorized_keys.<user> (D65, persönliche Admin-SSH-Keys je User): optional, kein /import (kein
  # RouterOS-Skript); base liest nur die Dateien der User aus users
  :foreach p,h in=$fx do={ :if ($p ~ "^authorized_keys\\.") do={ :set ($want->[:len $want]) ({$p;0;0}) } }
  :set ($want->[:len $want]) ({("hosts/" . $name . ".rsc");1;0})
  :set ($want->[:len $want]) ({"roles/base.rsc";1;1})
  :if ($rl ~ ",manager-backup,") do={ :set ($want->[:len $want]) ({"roles/manager.rsc";0;1}) }
  :foreach r in=[:toarray $role] do={ :set ($want->[:len $want]) ({("roles/" . $r . ".rsc");1;1}) }
  :set ($want->[:len $want]) ({("hosts/" . $name . ".post.rsc");1;0})
  :return $want
}
