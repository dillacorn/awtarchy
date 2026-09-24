# Awtarchy Yazi outbound drag

This managed plugin is adapted from [Joao-Queiroga/drag.yazi](https://github.com/Joao-Queiroga/drag.yazi).

Awtarchy uses it only for explicit outbound drag from Yazi:

- `e d`
- right-click an item or selected set -> **Drag out...**

The plugin launches `ripdrag` as a compact drag surface and exits after the first successful drop. Internal Yazi drag-to-folder remains handled by Awtarchy's existing Yazi Lua workflow.

Runtime dependency: stable `ripdrag` from the Arch User Repository.
