# LAB (e2e-mlag.sh, Phase MLAG): sw1/sw2 als Paar, srv1 per LACP an beiden
:global cfmMlag {
  "core"={"nodes"="sw1,sw2";"primary"="sw1";"peer"={"sw1"="ether3,ether4";"sw2"="ether2,ether3"};
    "bonds"={"srv1"={"id"=10;"ports"={"sw1"="ether5";"sw2"="ether4"};"profile"="trunk"}}}
}
